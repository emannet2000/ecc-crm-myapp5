
    (function () {
      localStorage.removeItem("token");
      var token = "cookie-session";
      var now = new Date();
      var today = [now.getFullYear(), String(now.getMonth() + 1).padStart(2, "0"), String(now.getDate()).padStart(2, "0")].join("-");

      var app = Elm.Main.init({
        node: document.getElementById("app"),
        flags: {
          token: token,
          today: today,
          theme: localStorage.getItem("theme")
        }
      });
      app.ports.storeToken.subscribe(function (token) {
        localStorage.removeItem("token");
        if (!token) fetch("/api/session/logout", {method:"POST",credentials:"same-origin"});
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
