# Discussion: Should discussion docs be committed

Date: 2026-08-18
Repo: `logos-blockchain-ui`
Participants: @alisher (asked), @fergie (builder), @senti (auditor)

## Question

Should `/discuss` decision records — `docs/discussions/YYYY-MM-DD-<slug>.md` — be committed to
the repo they concern, or kept as local scratch that the human promotes by hand?

These records come out of an adversarial review between the builder and the auditor: a decision,
the constraints the auditor forced, and what stayed open.

## Context supplied

Arguments **for** committing (supplied by @alisher):

- durable
- greppable
- auditable months later
- stops re-litigation

Arguments **against** (supplied by @alisher):

- repo noise
- records a debate rather than a code change
- may carry machine-specific paths

Precedent supplied by @alisher: this repo keeps issue drafts as an **untracked**
`docs/issue-drafts.ignore.md`. Two agents edited it independently; because it had no git history
there was nothing to merge and nothing to recover from. It was saved only by a stray snapshot copy.

## Positions

### @fergie — commit them

Evidence gathered in the repo, not asserted:

**1. The untracked arm of the experiment is the one that lost data.**

```
$ git ls-files docs/
docs/DOGFOOD-EXPERIMENTS.md
docs/VOUCHER-STATE-MAP.md
docs/img/leader-rewards-dashboard.png
docs/retro-log.md

$ git check-ignore -v docs/issue-drafts.ignore.md
.gitignore:15:*ignore*   docs/issue-drafts.ignore.md
```

Four docs tracked, one untracked. The untracked one is the one that got destroyed. That was
designed in: `.gitignore:15` is `*ignore*`, unanchored, so the file is invisible to plain
`git status` as well as uncommittable. No agent ever saw "you have uncommitted changes" — so
nobody stashed, `git checkout --` had nothing to restore, there was no reflog entry and no blob
to `git fsck`. Recovery cost is visible in the sizes: the snapshot that saved it was **6,358 B**,
the live file is **24,556 B**. Whatever was restored was a fraction of the state.

**2. Two of the three counter-arguments do not survive contact with the corpus.**

- *Machine-specific paths* — grepped `/home/`, `/Users/`, `/nix/store` across all four tracked
  docs **and** the untracked scratch file: **0 hits in every file.** Hypothetical here.
- *Repo noise* — `docs/` is 4 of 58 tracked files, 285 KB of 3.48 MB; 279 KB of that is the PNG
  screenshot already committed. The prose is ~47 KB. Noise is not the binding constraint.
- *Records a debate, not a code change* — **this one is real.** But it is an argument about which
  branch the record may ride, not about whether git should hold it.

**3. The layout, not the tracking, is what made the collision unrecoverable.**

Two agents appending to one 24 KB shared file collide in the same region with no base to diff
against. One file per record removes the shared region: two agents adding two files touch
disjoint paths and merge with nothing to resolve. A sibling repo already does this:

```
$ git ls-files issue-drafts/          # logos-notes
issue-drafts/issue-22-mnemonic-salt-persistence-unchecked.md
issue-drafts/issue-23-backup-import-false-success.md
issue-drafts/issue-24-phase0-save-false-success.md
```

`docs/discussions/YYYY-MM-DD-<slug>.md` is **already that shape**, so `/discuss`'s naming needs
no change — only tracking.

**4. The upstream-leak risk is real but is a branching rule, not a tracking rule.**

```
upstream = logos-blockchain/logos-blockchain-ui   (push disabled — PR only)
origin   = xAlisher/logos-blockchain-ui           (fork, 65 ahead / 6 behind)

git ls-tree upstream/master docs/       → empty (upstream has no docs/ at all)
scan of all 38 upstream branches        → 0 carry docs/
origin/compat/0.2.1-on-v0.2.1-base      → merge-base 4ed7837 with upstream/master, +41 commits,
                                          and carries docs/retro-log.md
```

That last branch is PR-shaped — cut from an upstream base — and it carries our retro log, whose
headings are `### Fails` and `### Skills extracted`: how *we* work, not how the code works. It was
never PR'd, so no harm done. It is the shape of the accident, and it is a branching mistake, not a
committing mistake.

**5. The two-agent experiment is no longer a claim — it was run.**

Three arms, same collision, three synthetic repos (`/tmp/merge-exp*`), scripts kept at
`/tmp/merge-exp-b/run.sh` and `runc.sh`.

*Arm A — one shared tracked file (`issue-drafts.ignore.md`'s layout, but tracked):*

```
CONFLICT (content): Merge conflict in docs/issue-drafts.md      exit=1
draft 3
<<<<<<< HEAD
draft A: mnemonic salt
=======
draft B: backup import
>>>>>>> agentB
```

Conflicts — but **both sides are in the file**. A human resolves it in ten seconds and loses nothing.

*Arm B — one file per record, different slugs:*

```
Merge made by the 'ort' strategy.                                exit=0
 docs/discussions/2026-08-18-backup-import.md | 1 +
$ git ls-files docs/discussions/
docs/discussions/2026-08-18-backup-import.md
docs/discussions/2026-08-18-mnemonic-salt.md
```

Clean. No conflict, no resolution step, both records present. This is the claim in §3, now measured.

*Arm B2 — one file per record, both agents pick the **same** slug:*

```
CONFLICT (add/add): Merge conflict in docs/discussions/2026-08-18-same-slug.md   exit=1
<<<<<<< HEAD
# A version
=======
# B version
>>>>>>> collB
```

Degrades to arm A: loud, and both versions survive. Worth a constraint (below), not a blocker.

*Arm C — untracked, matching `.gitignore`'s `*ignore*` — the arm that actually happened:*

```
A wrote bytes: 15174
--- git status after agent A ---
                                    ← empty. git never said there was work to lose.
B wrote bytes: 3274
--- recovery attempts ---
error: pathspec 'docs/issue-drafts.ignore.md' did not match any file(s) known to git
reflog entries touching the file: 0
dangling blobs from fsck: 0
A's content still present: 0
```

**No conflict. No error. No warning. Zero recovery paths, and A's 15 KB is gone.** That is the
whole argument: tracking does not prevent the collision, it converts a silent total loss into a
visible, resolvable one. Note the byte ratio reproduced the real incident's shape unprompted —
15,174 → 3,274 here, 24,556 → 6,358 there.

### @senti — auditor

(pending — Senti's constraints and objections are recorded under **Constraints** below once posted)

## Decision

*Pending — to be filled only after @senti replies APPROVED, then confirmed by @senti against what
it approved.*

## Constraints

*Pending — the constraints @senti forces on the decision go here.*

Fergie's proposed constraints, offered ahead of Senti's review:

1. **One file per record.** Never a shared append-only file. This is the property that makes
   concurrent agent edits merge cleanly, and it is the property `issue-drafts.ignore.md` lacked.
2. **Never on a PR-shaped branch.** Cut branches destined for `upstream` from `upstream/master`,
   never from our `master`. Process docs may live on `origin/master` only.
3. **Date + slug must be unique.** Arm B2 shows a slug collision degrades to an add/add conflict —
   loud and lossless, so this is hygiene, not a safety property. Check the directory before writing.
4. **Never put "ignore" in a filename in this repo.** `.gitignore:15` is `*ignore*`, unanchored —
   it silently swallows anything containing the substring, and invisibility is what turned "local
   scratch" into "unrecoverable".

## Open

- **Migrating `docs/issue-drafts.ignore.md`** to a tracked `docs/issue-drafts/`, one file per
  draft. It is the file that proved the point and it is still sitting in the same trap today.
  Not done as part of this discussion.
- **Enforcement.** The "no process docs on an upstream-based branch" rule is currently a
  convention. A pre-push or CI check — if `merge-base(HEAD, upstream/master)` is an upstream
  commit and the branch touches `docs/retro-log.md` or `docs/discussions/`, fail — was offered
  and not yet requested. It should be demonstrated firing on
  `origin/compat/0.2.1-on-v0.2.1-base` before being trusted.
- ~~**The two-agent merge experiment was not run.**~~ **Resolved** — run, three arms, results in
  §5 above. Caveat for the record: it was run in synthetic repos with synthetic content, not by
  replaying the real `issue-drafts.ignore.md` history (which does not exist — that is the point).
  It tests git's merge behaviour under each layout, which is the disputed claim; it does not test
  agent behaviour.
- **Whether `.gitignore:15`'s `*ignore*` should be narrowed** to an anchored pattern. Out of
  scope for this question, but it is the root cause of the precedent that motivated it.
