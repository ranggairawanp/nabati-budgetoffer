// One HCMS integration layer.
// Single place for all Supabase auth and RPC calls, shared by console and
// Budget Offering. Cloud mode uses Supabase Auth and the SECURITY DEFINER
// functions. Local mode is a demo fallback using localStorage.
// No backticks, no template literals, string concatenation only.
(function () {
  function cfg(k) { return (typeof window !== "undefined" && window[k]) || null; }
  var URL = cfg("SUPABASE_URL");
  var KEY = cfg("SUPABASE_ANON_KEY");
  var CLOUD = !!(URL && KEY && URL.indexOf("YOUR_") < 0 && typeof window !== "undefined" && window.supabase);
  var client = CLOUD ? window.supabase.createClient(URL, KEY) : null;

  var LS_KEY = "onehcms_flk_registry_v1";
  var DEMO = {
    "ta@nabati.demo": "TA",
    "hc@nabati.demo": "HC",
    "cb.specialist@nabati.demo": "SPECIALIST",
    "windha.cps@nabati.demo": "CPS",
    "frans.cpo@nabati.demo": "CPO",
    "groupceo@nabati.demo": "GCEO",
    "comben.admin@nabati.demo": "COMBEN_ADMIN"
  };
  var DEMO_PASS = "nabatiHC-123!";

  function lsLoad() { try { return JSON.parse(localStorage.getItem(LS_KEY) || "[]"); } catch (e) { return []; } }
  function lsSave(a) { localStorage.setItem(LS_KEY, JSON.stringify(a)); }
  function nowIso() { return new Date().toISOString(); }

  // Local demo chain parity (band only, without DOA escalation).
  function band(g) { g = g || ""; if (/^6B/.test(g)) return "TOP"; if (/^(5|6)/.test(g)) return "SENIOR"; return "BASE"; }
  function ladder() { return ["CPS", "CPO", "GCEO"]; }
  function firstRank(g) { return band(g) === "BASE" ? 1 : 2; }
  function topRank(g) { var b = band(g); return b === "BASE" ? 1 : b === "SENIOR" ? 2 : 3; }
  function chain(g) { var out = []; for (var r = firstRank(g); r <= topRank(g); r++) { out.push(ladder()[r - 1]); } return out; }

  var session = null;

  var Api = {
    mode: function () { return CLOUD ? "cloud" : "local"; },
    session: function () { return session; },

    signIn: async function (email, password) {
      if (CLOUD) {
        var r = await client.auth.signInWithPassword({ email: email, password: password });
        if (r.error) throw r.error;
        var uid = r.data.user.id;
        var role = await Api._resolveRole(uid);
        session = { email: email, role: role, user_id: uid };
        return session;
      }
      if (DEMO[email] && password === DEMO_PASS) {
        session = { email: email, role: DEMO[email], user_id: "local-" + DEMO[email] };
        return session;
      }
      throw new Error("Akun atau kata sandi salah");
    },

    _resolveRole: async function (uid) {
      var r = await client.from("authority_assignment").select("authority").eq("user_id", uid);
      if (r.error) throw r.error;
      var auths = (r.data || []).map(function (x) { return x.authority; });
      var order = ["TA", "HC", "SPECIALIST", "CPS", "CPO", "GCEO", "COMBEN_ADMIN"];
      for (var i = 0; i < order.length; i++) { if (auths.indexOf(order[i]) >= 0) return order[i]; }
      return auths[0] || null;
    },

    signOut: async function () {
      if (CLOUD) { try { await client.auth.signOut(); } catch (e) {} }
      session = null;
    },

    listCandidates: async function () {
      if (CLOUD) {
        var r = await client.from("candidates").select("*").order("created_at", { ascending: false });
        if (r.error) throw r.error;
        return r.data || [];
      }
      return lsLoad();
    },

    getCandidate: async function (code) {
      if (CLOUD) {
        var r = await client.from("candidates").select("*").eq("code", code).maybeSingle();
        if (r.error) throw r.error;
        return r.data;
      }
      return lsLoad().filter(function (c) { return c.code === code; })[0] || null;
    },

    registerCandidate: async function (code, name, email, position) {
      if (CLOUD) {
        var r = await client.rpc("fn_register_candidate", { p_code: code, p_name: name, p_email: email, p_position: position });
        if (r.error) throw r.error;
        return r.data;
      }
      var a = lsLoad();
      if (a.some(function (c) { return c.code === code; })) throw new Error("Kode sudah ada");
      a.unshift({ code: code, name: name, email: email, position: position, stage: "INVITED", flk: null, ol: null, agreement: null, created_at: nowIso() });
      lsSave(a);
      return { ok: true, code: code };
    },

    submitFlk: async function (code, flk) {
      if (CLOUD) {
        var r = await client.rpc("fn_submit_flk", { p_code: code, p_flk: flk });
        if (r.error) throw r.error;
        return r.data;
      }
      var a = lsLoad(), found = false;
      a = a.map(function (c) {
        if (c.code === code && c.stage === "INVITED") { found = true; return Object.assign({}, c, { flk: flk, stage: "FLK_SUBMITTED", submitted_at: nowIso() }); }
        return c;
      });
      if (!found) throw new Error("Kode tidak valid atau FLK sudah terkirim");
      lsSave(a);
      return { ok: true };
    },

    submitOl: async function (code, ol) {
      if (CLOUD) {
        var r = await client.rpc("fn_submit_ol", { p_code: code, p_ol: ol });
        if (r.error) throw r.error;
        return r.data;
      }
      var a = lsLoad();
      a = a.map(function (c) {
        if (c.code === code) { var o = Object.assign({}, ol, { approvals: [] }); return Object.assign({}, c, { ol: o, stage: "OL_REVIEW" }); }
        return c;
      });
      lsSave(a);
      return { ok: true };
    },

    approveOl: async function (code) {
      if (CLOUD) {
        var r = await client.rpc("fn_approve_ol", { p_code: code });
        if (r.error) throw r.error;
        return r.data;
      }
      var a = lsLoad(), res = null;
      a = a.map(function (c) {
        if (c.code !== code) return c;
        var ol = Object.assign({}, c.ol);
        var ch = chain(ol.grade);
        var ap = (ol.approvals || []).slice();
        if (ap.length >= ch.length) return c;
        ap.push({ authority: ch[ap.length], at: nowIso() });
        ol.approvals = ap;
        var fin = ap.length === ch.length;
        if (fin) { ol.signed = true; ol.approvedBy = ap[ap.length - 1]; }
        res = { stage: fin ? "OL_SIGNED" : "OL_REVIEW" };
        return Object.assign({}, c, { ol: ol, stage: fin ? "OL_SIGNED" : "OL_REVIEW" });
      });
      lsSave(a);
      return res || { ok: true };
    },

    returnOl: async function (code, note) {
      if (CLOUD) {
        var r = await client.rpc("fn_return_ol", { p_code: code, p_note: note || null });
        if (r.error) throw r.error;
        return r.data;
      }
      var a = lsLoad();
      a = a.map(function (c) { if (c.code === code) { var ol = Object.assign({}, c.ol, { approvals: [] }); return Object.assign({}, c, { ol: ol, stage: "OL_DRAFT" }); } return c; });
      lsSave(a);
      return { ok: true };
    },

    finalizeAgreement: async function (code, agreement) {
      if (CLOUD) {
        var r = await client.rpc("fn_finalize_agreement", { p_code: code, p_agreement: agreement });
        if (r.error) throw r.error;
        return r.data;
      }
      var a = lsLoad();
      a = a.map(function (c) { if (c.code === code && c.stage === "OL_SIGNED") { return Object.assign({}, c, { agreement: agreement, stage: "AGREEMENT_DONE" }); } return c; });
      lsSave(a);
      return { ok: true };
    },

    getInvite: async function (code) {
      if (CLOUD) {
        var r = await client.rpc("fn_get_invite", { p_code: code });
        if (r.error) throw r.error;
        return r.data;
      }
      var c = (lsLoad().filter(function (x) { return x.code === code; })[0]) || null;
      if (!c || c.stage !== "INVITED") throw new Error("invalid code");
      return c;
    },

    shortlistCandidate: async function (code) {
      if (CLOUD) { var r = await client.rpc("fn_shortlist_candidate", { p_code: code }); if (r.error) throw r.error; return r.data; }
      var a = lsLoad(), f = false;
      a = a.map(function (c) { if (c.code === code && c.stage === "FLK_SUBMITTED") { f = true; return Object.assign({}, c, { stage: "SHORTLISTED" }); } return c; });
      if (!f) throw new Error("Hanya kandidat FLK Masuk yang bisa diloloskan"); lsSave(a); return { ok: true, stage: "SHORTLISTED" };
    },

    rejectCandidate: async function (code, note) {
      if (CLOUD) { var r = await client.rpc("fn_reject_candidate", { p_code: code, p_note: note || null }); if (r.error) throw r.error; return r.data; }
      var a = lsLoad(), f = false;
      a = a.map(function (c) { if (c.code === code && (c.stage === "FLK_SUBMITTED" || c.stage === "SHORTLISTED")) { f = true; return Object.assign({}, c, { stage: "REJECTED" }); } return c; });
      if (!f) throw new Error("Kandidat tidak bisa ditolak pada tahap ini"); lsSave(a); return { ok: true, stage: "REJECTED" };
    },

    restoreCandidate: async function (code) {
      if (CLOUD) { var r = await client.rpc("fn_restore_candidate", { p_code: code }); if (r.error) throw r.error; return r.data; }
      var a = lsLoad(), f = false;
      a = a.map(function (c) { if (c.code === code && c.stage === "REJECTED") { f = true; return Object.assign({}, c, { stage: "FLK_SUBMITTED" }); } return c; });
      if (!f) throw new Error("Hanya kandidat Tidak Lolos yang bisa dikembalikan"); lsSave(a); return { ok: true, stage: "FLK_SUBMITTED" };
    },

    reviseCandidate: async function (code, name, email, position) {
      if (CLOUD) { var r = await client.rpc("fn_revise_candidate", { p_code: code, p_name: name || null, p_email: email || null, p_position: position || null }); if (r.error) throw r.error; return r.data; }
      var a = lsLoad();
      a = a.map(function (c) { if (c.code === code && c.stage !== "AGREEMENT_DONE") { return Object.assign({}, c, { name: name || c.name, email: email || c.email, position: position || c.position }); } return c; });
      lsSave(a); return { ok: true };
    },

    requestCorrection: async function (code, note) {
      if (CLOUD) { var r = await client.rpc("fn_request_correction", { p_code: code, p_note: note }); if (r.error) throw r.error; return r.data; }
      var a = lsLoad();
      a = a.map(function (c) { if (c.code === code) { var flk = Object.assign({}, c.flk || {}, { correctionRequested: true }); return Object.assign({}, c, { flk: flk }); } return c; });
      lsSave(a); return { ok: true, correctionRequested: true };
    },

    deleteCandidate: async function (code) {
      if (CLOUD) {
        var r = await client.rpc("fn_delete_candidate", { p_code: code });
        if (r.error) throw r.error;
        return r.data;
      }
      var a = lsLoad().filter(function (c) { return c.code !== code; });
      lsSave(a);
      return { ok: true };
    }
  };

  if (typeof window !== "undefined") window.HCMSApi = Api;
  if (typeof module !== "undefined" && module.exports) module.exports = Api;
})();
