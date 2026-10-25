// GNOME Shell search provider (org.gnome.Shell.SearchProvider2) for recently
// opened VS Code folders and workspaces. D-Bus activated; modelled on the
// Claude desktop app's provider.
//
// Source of recents: ~/.config/Code/User/workspaceStorage/*/workspace.json,
// ranked by the mtime of that workspace's state.vscdb (updated whenever the
// folder is used). This build of VS Code keeps no
// history.recentlyOpenedPathsList in globalStorage/state.vscdb.

import Gio from "gi://Gio";
import GLib from "gi://GLib";
import GioUnix from "gi://GioUnix";

const BUS_NAME = "io.github.jannik_el.VSCodeSearchProvider";
const OBJECT_PATH = "/io/github/jannik_el/VSCodeSearchProvider";
const DESKTOP_ID = "code_code.desktop";
const EXECUTABLE = "code";
const MAX_RESULTS = 8;
const CACHE_USEC = 3 * 1000 * 1000;
const IDLE_EXIT_SECONDS = 120;
const STORAGE_DIRS = ["Code", "Code - Insiders", "VSCodium"].map((d) =>
  GLib.build_filenamev([GLib.get_user_config_dir(), d, "User", "workspaceStorage"]),
);

const IFACE = `
<node>
  <interface name="org.gnome.Shell.SearchProvider2">
    <method name="GetInitialResultSet">
      <arg type="as" name="terms" direction="in"/>
      <arg type="as" name="results" direction="out"/>
    </method>
    <method name="GetSubsearchResultSet">
      <arg type="as" name="previous_results" direction="in"/>
      <arg type="as" name="terms" direction="in"/>
      <arg type="as" name="results" direction="out"/>
    </method>
    <method name="GetResultMetas">
      <arg type="as" name="identifiers" direction="in"/>
      <arg type="aa{sv}" name="metas" direction="out"/>
    </method>
    <method name="ActivateResult">
      <arg type="s" name="identifier" direction="in"/>
      <arg type="as" name="terms" direction="in"/>
      <arg type="u" name="timestamp" direction="in"/>
    </method>
    <method name="LaunchSearch">
      <arg type="as" name="terms" direction="in"/>
      <arg type="u" name="timestamp" direction="in"/>
    </method>
  </interface>
</node>`;

const decoder = new TextDecoder();
const HOME = GLib.get_home_dir();
const UNSAFE_LABEL_CHARS =
  /[\u0000-\u001f\u007f-\u009f‎‏‪-‮⁦-⁩]/g;

function readJson(path) {
  try {
    const [ok, bytes] = Gio.File.new_for_path(path).load_contents(null);
    return ok ? JSON.parse(decoder.decode(bytes)) : null;
  } catch (_e) {
    return null;
  }
}

function mtime(path) {
  try {
    return Gio.File.new_for_path(path)
      .query_info("time::modified", Gio.FileQueryInfoFlags.NONE, null)
      .get_attribute_uint64("time::modified");
  } catch (_e) {
    return 0;
  }
}

function tildify(path) {
  return path === HOME || path.startsWith(`${HOME}/`)
    ? `~${path.slice(HOME.length)}`
    : path;
}

function clean(text) {
  return text.replace(UNSAFE_LABEL_CHARS, " ");
}

/** {uri, kind, title, description, path?, at} or null for unusable entries. */
function project(uri, kind, at) {
  let path = null;
  let location;
  if (uri.startsWith("file://")) {
    try {
      path = GLib.filename_from_uri(uri)[0];
    } catch (_e) {
      return null;
    }
    if (!GLib.file_test(path, GLib.FileTest.EXISTS)) {
      return null;
    }
    location = tildify(path);
  } else if (uri.startsWith("vscode-remote://")) {
    // vscode-remote://<authority>/<path>, authority like ssh-remote+host
    const rest = uri.slice("vscode-remote://".length);
    const slash = rest.indexOf("/");
    const authority = decodeURIComponent(slash < 0 ? rest : rest.slice(0, slash));
    const remotePath = slash < 0 ? "/" : decodeURIComponent(rest.slice(slash));
    location = `${authority}: ${remotePath}`;
  } else {
    return null;
  }
  const base = GLib.path_get_basename(
    path ?? decodeURIComponent(uri.replace(/\/+$/, "")),
  );
  const title =
    kind === "workspace" ? base.replace(/\.code-workspace$/, "") : base;
  return {
    uri,
    kind,
    path,
    at,
    title: clean(title),
    description: clean(kind === "workspace" ? `Workspace · ${location}` : location),
    hay: `${title} ${location} ${path ?? ""}`.toLowerCase(),
  };
}

let cache = { at: 0, projects: [] };

function loadProjects() {
  const now = GLib.get_monotonic_time();
  if (now - cache.at < CACHE_USEC) {
    return cache.projects;
  }
  const byUri = new Map();
  for (const root of STORAGE_DIRS) {
    let en;
    try {
      en = Gio.File.new_for_path(root).enumerate_children(
        "standard::name,standard::type",
        Gio.FileQueryInfoFlags.NOFOLLOW_SYMLINKS,
        null,
      );
    } catch (_e) {
      continue;
    }
    for (let info = en.next_file(null); info !== null; info = en.next_file(null)) {
      if (info.get_file_type() !== Gio.FileType.DIRECTORY) {
        continue;
      }
      const dir = GLib.build_filenamev([root, info.get_name()]);
      const ws = readJson(GLib.build_filenamev([dir, "workspace.json"]));
      if (ws === null) {
        continue;
      }
      const [uri, kind] =
        typeof ws.folder === "string"
          ? [ws.folder, "folder"]
          : typeof ws.workspace === "string"
            ? [ws.workspace, "workspace"]
            : [null, null];
      if (uri === null) {
        continue;
      }
      const at = Math.max(
        mtime(GLib.build_filenamev([dir, "state.vscdb"])),
        mtime(dir),
      );
      const prev = byUri.get(uri);
      if (prev && prev.at >= at) {
        continue;
      }
      const p = project(uri, kind, at);
      if (p !== null) {
        byUri.set(uri, p);
      }
    }
  }
  const projects = [...byUri.values()].sort((a, b) => b.at - a.at);
  cache = { at: now, projects };
  return projects;
}

function search(terms) {
  const needles = terms.map((t) => t.toLowerCase()).filter((t) => t.length > 0);
  if (needles.length === 0) {
    return [];
  }
  return loadProjects()
    .filter((p) => needles.every((n) => p.hay.includes(n)))
    .slice(0, MAX_RESULTS)
    .map((p) => p.uri);
}

function appInfo() {
  try {
    return GioUnix.DesktopAppInfo.new(DESKTOP_ID);
  } catch (_e) {
    return null;
  }
}

function spawnCode(args) {
  GLib.spawn_async(null, [EXECUTABLE, ...args], null, GLib.SpawnFlags.SEARCH_PATH, null);
}

class Provider {
  constructor(onCall) {
    this._onCall = onCall;
  }

  GetInitialResultSet(terms) {
    this._onCall();
    return search(terms);
  }

  GetSubsearchResultSet(_previous, terms) {
    this._onCall();
    return search(terms);
  }

  GetResultMetas(ids) {
    this._onCall();
    const app = appInfo();
    const icon = app?.get_icon()?.serialize() ?? null;
    const byUri = new Map(loadProjects().map((p) => [p.uri, p]));
    // GNOME Shell requires exactly one meta per requested id.
    return ids.map((id) => {
      const p = byUri.get(id);
      const meta = {
        id: new GLib.Variant("s", id),
        name: new GLib.Variant("s", p ? p.title : "VS Code project"),
        description: new GLib.Variant("s", p ? p.description : ""),
      };
      if (icon !== null) {
        meta.icon = icon;
      }
      return meta;
    });
  }

  ActivateResult(id, _terms, _timestamp) {
    this._onCall();
    const p = loadProjects().find((x) => x.uri === id);
    if (!p) {
      return;
    }
    if (p.path !== null) {
      // Open through the .desktop file so launch env matches the app launcher.
      const app = appInfo();
      if (app !== null) {
        app.launch([Gio.File.new_for_path(p.path)], null);
      } else {
        spawnCode([p.path]);
      }
    } else {
      spawnCode([p.kind === "workspace" ? "--file-uri" : "--folder-uri", p.uri]);
    }
  }

  LaunchSearch(_terms, _timestamp) {
    this._onCall();
    const app = appInfo();
    if (app !== null) {
      app.launch([], null);
    } else {
      spawnCode([]);
    }
  }
}

const loop = new GLib.MainLoop(null, false);
let idleTimer = 0;
function touch() {
  if (idleTimer !== 0) {
    GLib.source_remove(idleTimer);
  }
  idleTimer = GLib.timeout_add_seconds(GLib.PRIORITY_DEFAULT, IDLE_EXIT_SECONDS, () => {
    loop.quit();
    return GLib.SOURCE_REMOVE;
  });
}

const exported = Gio.DBusExportedObject.wrapJSObject(IFACE, new Provider(touch));
Gio.bus_own_name(
  Gio.BusType.SESSION,
  BUS_NAME,
  Gio.BusNameOwnerFlags.NONE,
  (connection) => exported.export(connection, OBJECT_PATH),
  null,
  () => loop.quit(),
);
touch();
loop.run();
