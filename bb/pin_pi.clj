(ns pin-pi
  "Keep a known-good rev of the `pi` flake input, and restore it when an
  update breaks the build.

  pi's Nix build reads model data from the catalog pinned in upstream
  nix/model-catalog.json. A source change that needs new model data breaks
  the Nix build until upstream updates that pin. At the commit that updates
  the pin, the code and the pinned catalog agree, so that commit is a
  likely good rev.

  The known-good rev is kept in bb/pi-pin.edn (tracked).

  Subcommands:
    (none)   Show the locked rev, the pin, and the latest catalog commit.
    revert   Lock pi to the pinned rev.
    refresh  Replace the pin with the latest catalog commit, if that commit
             is newer than the pin.
    current  Replace the pin with the rev in flake.lock.

  Rule: run `current` only after a build with the current flake.lock
  succeeds. `current` does not build anything; it records what you tell it
  is good."
  (:require [babashka.cli :as cli]
            [babashka.fs :as fs]
            [babashka.http-client :as http]
            [babashka.process :refer [shell]]
            [cheshire.core :as json]
            [clojure.edn :as edn]
            [clojure.pprint :as pprint]
            [clojure.string :as str]))

(def repo "earendil-works/pi")
(def catalog-path "nix/model-catalog.json")
(def input-name "pi")
(def pin-path "bb/pi-pin.edn")

(def cli-spec
  {:flake   {:desc "Flake directory" :default "."}
   :branch  {:desc "Upstream branch to search for catalog commits" :default "main"}
   :dry-run {:desc "Report what would change; write nothing" :coerce :boolean}
   :help    {:desc "Show this help" :coerce :boolean :alias :h}})

(defn- fail [& msg]
  (binding [*out* *err*] (println (str "error: " (str/join " " msg))))
  (System/exit 1))

(defn- short-rev [rev] (subs rev 0 (min 7 (count rev))))

;; ── GitHub ────────────────────────────────────────────────────────────────

(defn- github-get [path query]
  (let [token (System/getenv "GITHUB_TOKEN")
        resp  (http/get (str "https://api.github.com/repos/" repo path)
                        {:query-params query
                         :headers (cond-> {"Accept" "application/vnd.github+json"}
                                    token (assoc "Authorization" (str "Bearer " token)))
                         :throw false})]
    (when-not (= 200 (:status resp))
      (fail "GitHub API" path "returned HTTP" (:status resp) "-" (:body resp)))
    (json/parse-string (:body resp) true)))

(defn- last-catalog-commit
  "The newest commit on `branch` that changed the catalog pin."
  [branch]
  (let [[c] (github-get "/commits" {"path" catalog-path "sha" branch "per_page" "1"})]
    (when-not c
      (fail "no commit on" branch "changes" catalog-path))
    {:rev     (:sha c)
     :date    (get-in c [:commit :committer :date])
     :subject (first (str/split-lines (get-in c [:commit :message])))}))

(defn- compare-revs
  "How `head` relates to `base`: {:status \"ahead\"|\"behind\"|\"identical\"|\"diverged\"
  :ahead-by n :behind-by n}. \"ahead\" means head contains base plus more commits."
  [base head]
  (let [r (github-get (str "/compare/" base "..." head) {"per_page" "1"})]
    {:status (:status r) :ahead-by (:ahead_by r) :behind-by (:behind_by r)}))

(defn- describe [{:keys [status ahead-by behind-by]}]
  (case status
    "identical" "identical"
    "ahead"     (str ahead-by " commits newer")
    "behind"    (str behind-by " commits older")
    "diverged"  (str "diverged (" ahead-by " ahead, " behind-by " behind)")
    status))

;; ── Local state ───────────────────────────────────────────────────────────

(defn- lock-file [flake-dir] (str (fs/path flake-dir "flake.lock")))
(defn- pin-file [flake-dir] (str (fs/path flake-dir pin-path)))

(defn- locked-pi [flake-dir]
  (let [f (lock-file flake-dir)
        _ (when-not (fs/exists? f) (fail "no flake.lock in" flake-dir))
        node (get-in (json/parse-string (slurp f)) ["nodes" input-name])]
    (when-not node
      (fail "no" input-name "node in" f))
    {:rev      (get-in node ["locked" "rev"])
     :date     (str (java.time.Instant/ofEpochSecond (get-in node ["locked" "lastModified"])))
     :original (get node "original")}))

(defn- read-pin [flake-dir]
  (let [f (pin-file flake-dir)]
    (when (fs/exists? f)
      (edn/read-string (slurp f)))))

(defn- write-pin! [flake-dir pin]
  (fs/create-dirs (fs/parent (pin-file flake-dir)))
  (spit (pin-file flake-dir)
        (str ";; Known-good rev of the pi flake input. Managed by `bb pin-pi`.\n"
             ";; Run `bb pin-pi current` only after a build with flake.lock succeeds.\n"
             (with-out-str (pprint/pprint pin)))))

(defn- show [label {:keys [rev date]} & more]
  (println (format "%-8s %s %s%s" label (short-rev rev) date
                   (if (seq more) (str " " (str/join " " more)) ""))))

;; ── Subcommands ───────────────────────────────────────────────────────────

(defn- status [{:keys [flake-dir opts]}]
  (let [lock    (locked-pi flake-dir)
        pin     (read-pin flake-dir)
        catalog (last-catalog-commit (:branch opts))]
    (show "lock:" lock)
    (if pin
      (show "pin:" pin (str "(" (name (:source pin)) ")"))
      (println "pin:     none - run `bb pin-pi current` after a good build"))
    (show "catalog:" catalog "-" (:subject catalog))
    (when pin
      (println "lock vs pin:   " (describe (compare-revs (:rev pin) (:rev lock))))
      (println "catalog vs pin:" (describe (compare-revs (:rev pin) (:rev catalog)))))))

(defn- revert [{:keys [flake-dir opts]}]
  (let [lock (locked-pi flake-dir)
        pin  (or (read-pin flake-dir) (fail "no pin in" (pin-file flake-dir)))]
    (show "lock:" lock)
    (show "pin:" pin)
    (cond
      (= (:rev lock) (:rev pin)) (println "flake.lock already has the pinned rev.")
      (:dry-run opts)            (println "dry run: flake.lock not changed.")
      :else
      (let [{:keys [exit]} (shell {:dir flake-dir :continue true}
                                  "nix" "flake" "lock" "--impure" "--override-input" input-name
                                  (str "github:" repo "/" (:rev pin)))]
        (when-not (zero? exit) (fail "nix flake lock failed with exit code" exit))
        (let [after (locked-pi flake-dir)]
          (when-not (= (:rev after) (:rev pin))
            (fail "flake.lock has" input-name "at" (:rev after) "- expected" (:rev pin)))
          (when-not (= (:original after) (:original lock))
            (fail "the original of" input-name "changed:" (pr-str (:original after))))
          (println (str "locked " input-name " to " (short-rev (:rev pin)) ".")))))))

(defn- refresh [{:keys [flake-dir opts]}]
  (let [pin     (read-pin flake-dir)
        catalog (last-catalog-commit (:branch opts))
        new-pin {:rev (:rev catalog) :date (:date catalog) :source :catalog}]
    (when pin (show "pin:" pin))
    (show "catalog:" catalog "-" (:subject catalog))
    (let [rel (when pin (compare-revs (:rev pin) (:rev catalog)))]
      (case (:status rel "none")
        ("identical" "behind") (println "pin unchanged: the catalog commit is not newer.")
        "diverged" (fail "the pin and the catalog commit have diverged:" (describe rel))
        ("ahead" "none")
        (if (:dry-run opts)
          (println "dry run: would pin" (short-rev (:rev catalog)))
          (do (write-pin! flake-dir new-pin)
              (println (str "pinned " (short-rev (:rev catalog)) " in " pin-path "."))))
        (fail "unexpected compare status" (pr-str (:status rel)))))))

(defn- current [{:keys [flake-dir opts]}]
  (let [lock (locked-pi flake-dir)
        pin  (read-pin flake-dir)]
    (when pin (show "pin:" pin))
    (show "lock:" lock)
    (cond
      (= (:rev lock) (:rev pin)) (println "pin already has the locked rev.")
      (:dry-run opts)            (println "dry run: would pin" (short-rev (:rev lock)))
      :else
      (do (write-pin! flake-dir {:rev (:rev lock) :date (:date lock) :source :current})
          (println (str "pinned " (short-rev (:rev lock)) " in " pin-path "."))))))

;; ── Entry point ───────────────────────────────────────────────────────────

(defn- help [_]
  (println "Usage: bb pin-pi [revert|refresh|current] [options]\n")
  (println (:doc (meta (the-ns 'pin-pi))))
  (println)
  (println (cli/format-opts {:spec cli-spec})))

(defn- run [f]
  (fn [{:keys [opts] :as m}]
    (if (:help opts)
      (help m)
      (f (assoc m :flake-dir (str (fs/canonicalize (:flake opts))))))))

(defn -main [& args]
  (cli/dispatch
   [{:cmds ["revert"]  :fn (run revert)  :spec cli-spec}
    {:cmds ["refresh"] :fn (run refresh) :spec cli-spec}
    {:cmds ["current"] :fn (run current) :spec cli-spec}
    {:cmds []          :fn (run status)  :spec cli-spec}]
   args))
