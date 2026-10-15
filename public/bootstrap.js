
    (function () {
      localStorage.removeItem("token");
      var token = "cookie-session";
      var now = new Date();
      var today = [now.getFullYear(), String(now.getMonth() + 1).padStart(2, "0"), String(now.getDate()).padStart(2, "0")].join("-");

      var app = Elm.Main.init({
        node: document.getElementById("app"),
        flags: {
          token: token,
          logoutPending: sessionStorage.getItem('ecc:logout-pending:v1') === 'true',
          today: today,
          theme: localStorage.getItem("theme")
        }
      });
      app.ports.storeToken.subscribe(function () {
        localStorage.removeItem("token");
      });
      // Only an explicit sign-out may revoke the shared browser session. A stale
      // authentication failure in one tab must not revoke a newer login elsewhere.
      app.ports.logoutSession.subscribe(async function () {
        sessionStorage.setItem('ecc:logout-pending:v1', 'true');
        const controller = new AbortController();
        const timer = setTimeout(function () { controller.abort(); }, 12000);
        try {
          const response = await fetch('/api/session/logout', {method:'POST',credentials:'same-origin',signal:controller.signal});
          const data = await response.json();
          if (!response.ok || response.status === 202 || data.status !== 'ok') throw new Error('pending');
          sessionStorage.removeItem('ecc:logout-pending:v1');
          app.ports.logoutFinished.send({ok:true,message:'Signed out.'});
        } catch (_) {
          app.ports.logoutFinished.send({ok:false,message:'Server sign-out could not be confirmed. Reconnect and retry to finish signing out.'});
        } finally { clearTimeout(timer); }
      });
      app.ports.preserveSessionDrafts.subscribe(function (owner) {
        window.CRMSessionDrafts?.capture(owner);
      });
      const currentUser = () => document.querySelector('#workspace-navigation')?.getAttribute('data-user-id');
      function accountChanged() {
        if (window.CRMAccountChanging) return;
        window.CRMAccountChanging = true;
        window.CRMSessionDrafts?.capture(currentUser());
        document.body.inert = true;
        document.body.style.visibility = 'hidden';
        location.replace('/');
      }
      app.ports.sessionIdentity.subscribe(function (id) {
        try { localStorage.setItem('ecc:account-id:v1', id); } catch (_) {}
      });
      window.addEventListener('storage', function (event) {
        if (event.key === 'ecc:account-id:v1' && event.newValue && currentUser() && event.newValue !== currentUser()) accountChanged();
      });
      window.addEventListener('crm:account-changed', accountChanged);
      let checkingAccount = false;
      window.addEventListener('focus', async function () {
        const expected = currentUser();
        if (!expected || checkingAccount) return;
        checkingAccount = true;
        try {
          const response = await fetch('/api/me', {credentials:'same-origin'});
          if (response.ok) {
            const data = await response.json();
            if (data.user?.id && data.user.id !== expected && currentUser() === expected) accountChanged();
          }
        } catch (_) {} finally { checkingAccount = false; }
      });
      // Elm owns draft state; this adapter invokes the browser's unload API.
      var protectUnsaved = false;
      app.ports.protectUnsaved.subscribe(function (value) { protectUnsaved = value; });
      window.addEventListener("beforeunload", function (event) {
        if (protectUnsaved) { event.preventDefault(); event.returnValue = ""; }
      });
      app.ports.storeTheme.subscribe(function (theme) { localStorage.setItem("theme", theme); window.dispatchEvent(new Event("crm:theme-changed")); });
      window.addEventListener("crm:record-changed", function(event) { app.ports.recordChanged.send(event.detail || ""); });
      app.ports.workReady.subscribe(function () { window.dispatchEvent(new Event("crm:my-work-ready")); });
      app.ports.downloadFile.subscribe(function (file) {
        var url = URL.createObjectURL(new Blob([file.content], { type: file.mime }));
        var link = document.createElement("a");
        link.href = url;
        link.download = file.filename;
        document.body.appendChild(link);
        link.click();
        link.remove();
        setTimeout(function () { URL.revokeObjectURL(url); }, 1000);
      });
      app.ports.printElement.subscribe(function (id) {
        var source = document.getElementById(id);
        if (!source) { app.ports.printResult.send(false); return; }
        var popup = window.open("", "_blank");
        if (!popup) { app.ports.printResult.send(false); return; }
        app.ports.printResult.send(true);
        popup.opener = null;
        popup.document.title = "ECC Workspace management report";
        popup.document.documentElement.lang = document.documentElement.lang || "en";
        var stylesheet = popup.document.createElement("link");
        stylesheet.rel = "stylesheet";
        stylesheet.href = "/public/management-report-elm.css";
        popup.document.head.appendChild(stylesheet);
        var copy = source.cloneNode(true);
        copy.querySelectorAll(".actions,.filters,.status").forEach(function (node) { node.remove(); });
        popup.document.body.appendChild(copy);
        stylesheet.onload = function () { popup.focus(); popup.print(); };
      });
    })();

window.crmWorkspaceInteractions = new window.CRMWorkspaceInteractions(document);
window.crmWorkspaceInteractions.start();
