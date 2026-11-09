/* Check for updates, on demand: runs Derp's own updater (derp-update, or
 * derp-update.ps1 on Windows, which otherwise runs every 6 hours) and says how
 * it went. The updater installs a newer Derp and stages a newer engine; the
 * engine is swapped in the next time Derp opens. Settings → Derp → Updates. */

const lazy = {};
ChromeUtils.defineESModuleGetters(lazy, {
  Subprocess: "resource://gre/modules/Subprocess.sys.mjs",
});

export const DerpUpdates = {
  /** idle, checking, current, updated, engine, busy or failed. */
  state: "idle",
  installed: "",
  newVersion: "",
  checkedAt: 0,

  /** Derp's folder: the one the features (resource://derp) are in. */
  get home() {
    const handler = Services.io.getProtocolHandler("resource").QueryInterface(Ci.nsIResProtocolHandler);
    return handler.getSubstitution("derp").QueryInterface(Ci.nsIFileURL).file.parent.path;
  },

  get windows() {
    return Services.appinfo.OS === "WINNT";
  },

  async version() {
    try {
      return (await IOUtils.readUTF8(PathUtils.join(this.home, "VERSION"))).trim();
    } catch {
      return "";
    }
  },

  /** A newer engine, fetched and waiting for Derp to restart. */
  async stagedEngine() {
    const home = this.home;
    const marks =
      Services.appinfo.OS === "Darwin"
        ? [PathUtils.join(home, "Derp.app.next", "Contents", ".derp-ready")]
        : [PathUtils.join(home, "firefox.next", ".derp-ready")];
    for (const mark of marks) {
      if (await IOUtils.exists(mark)) {
        return true;
      }
    }
    return false;
  },

  set(state, extra = {}) {
    Object.assign(this, { state }, extra);
    Services.obs.notifyObservers(null, "derp-updates-changed");
  },

  async load() {
    this.installed = await this.version();
    Services.obs.notifyObservers(null, "derp-updates-changed");
  },

  async check() {
    if (this.state === "checking") {
      return;
    }
    const home = this.home;
    const before = await this.version();
    this.set("checking", { installed: before });
    try {
      // The updater does one run at a time; one may be under way already.
      if (!this.windows && (await IOUtils.exists(PathUtils.join(home, ".update.lock.d")))) {
        this.set("busy");
        return;
      }
      const updater = PathUtils.join(home, "lib", this.windows ? "derp-update.ps1" : "derp-update");
      if (!(await IOUtils.exists(updater))) {
        throw new Error(`no updater at ${updater}`);
      }
      const command = this.windows ? await lazy.Subprocess.pathSearch("powershell.exe") : "/bin/bash";
      const args = this.windows
        ? ["-NoProfile", "-NonInteractive", "-WindowStyle", "Hidden", "-ExecutionPolicy", "Bypass", "-File", updater]
        : [updater];
      const run = await lazy.Subprocess.call({
        command,
        arguments: args,
        environment: { DERP_HOME: home },
        environmentAppend: true,
        stderr: "stdout",
      });
      // Read what it says as it goes (else a full pipe would stall it).
      let output = "";
      for (let chunk; (chunk = await run.stdout.readString()); ) {
        output += chunk;
      }
      const { exitCode } = await run.wait();
      if (exitCode !== 0) {
        throw new Error(`updater exited with ${exitCode}: ${output.trim().split("\n").pop() || ""}`);
      }
      const after = await this.version();
      const extra = { installed: after, checkedAt: Date.now() };
      if (after && after !== before) {
        this.set("updated", { ...extra, newVersion: after });
      } else if (await this.stagedEngine()) {
        this.set("engine", extra);
      } else {
        this.set("current", extra);
      }
    } catch (e) {
      console.warn("Derp: checking for updates failed", e);
      this.set("failed");
    }
  },
};
