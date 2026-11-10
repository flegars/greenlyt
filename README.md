# greenlyt

Plugin Claude Code qui fait passer un besoin à une **PR draft prête à relire** :

1. une spec est rédigée, puis validée par toi ;
2. un agent développeur implémente, un agent relecteur indépendant le challenge ;
3. la boucle tourne jusqu'à ce que **les tests soient verts et le relecteur d'accord** ;
4. toute liberté prise hors spec t'est signalée avant l'ouverture de la PR.

## Installation

```
/plugin marketplace add flegars/greenlyt
/plugin install greenlyt@greenlyt
```

## Utilisation

```
/greenlyt:init                 # une fois par projet → .greenlyt/config.json
/greenlyt:spec "<besoin>"      # → docs/greenlyt/specs/<slug>.md, validée par toi
/greenlyt:run <slug>           # boucle → PR draft, ou rapport d'échec
```

Les specs et les rapports sont écrits dans `docs/greenlyt/` (configurable via `docsDir`).

## Ce que fait la boucle

À chaque tour :

1. l'agent `implementer` implémente la spec et écrit les tests, en tenant compte des objections du tour précédent ;
2. la CLI du plugin exécute **réellement** la commande de test (`testCommand`) : son code de sortie est le seul qui fait foi ;
3. l'agent `reviewer`, en lecture seule, rend un verdict JSON : `approved`, `objections`, `deviations` (libertés prises hors spec), `specIssues` (ambiguïtés de la spec) ;
4. le tour est commité sur la branche de travail `greenlyt/<slug>`.

- **Succès** (tests verts + relecteur d'accord) : les libertés éventuelles te sont soumises (accepter ou corriger), puis la branche est poussée et une **PR draft** est ouverte. Sa description reprend la spec, le tableau AC → preuves, les tours et les libertés acceptées.
- **Budget épuisé** : aucun push, aucune PR. Un rapport d'échec liste les tests rouges, les objections non résolues et des **questions ouvertes** pour recentrer la spec. Mets la spec à jour avec `/greenlyt:spec <slug>`, puis relance `/greenlyt:run <slug>` : le run reprend sur la même branche avec un budget neuf.

`/greenlyt:run` refuse de démarrer si l'arbre de travail n'est pas propre, si la spec n'est pas validée ou si la suite de tests est déjà rouge sur la branche de base.

## Configuration — `.greenlyt/config.json`

| Clé | Défaut | Rôle |
|---|---|---|
| `docsDir` | `docs/greenlyt` | Dossier des specs (`specs/`) et des rapports (`runs/`) |
| `testCommand` | — (obligatoire) | Commande de test, exécutée via `bash -c` à la racine du repo |
| `maxAttempts` | `5` | Plafond de tours par run (corrections de libertés comprises) |
| `protectedBranches` | `["main","master","develop"]` | Branches sur lesquelles commit, push, reset `--hard` et rebase sont bloqués |
| `branchPrefix` | `greenlyt/` | Préfixe de la branche de travail |
| `deviations` | `ask` | `ask` : s'arrêter pour faire trancher les libertés ; `report` : seulement les lister dans la PR |
| `forge.type` | `github` | `github` (via `gh`) ou `azure-devops` (via `az repos`) |
| `forge.remote` | `origin` | Remote git de push |
| `forge.baseBranch` | `main` | Branche de départ et cible de la PR |
| `forge.organization`, `forge.project`, `forge.repository` | — | Azure DevOps uniquement |

Des exemples par stack et par forge sont dans [`examples/config/`](examples/config/).

## Garde-fous

- **Plafond de tentatives** : au-delà de `maxAttempts`, la boucle s'arrête avec un rapport d'échec, sans jamais maquiller un échec en succès.
- **Hook `Stop`** : empêche Claude de s'arrêter au milieu d'un run. Il respecte `stop_hook_active` : s'il est réveillé deux fois sans que le compteur de tours ait avancé, il laisse s'arrêter et marque le run `stalled`.
- **Garde des branches protégées** (hook `PreToolUse`) : refuse `git commit`, `git push`, `git reset --hard` et `git rebase` sur une branche protégée, ainsi que tout push qui la vise (`git push origin HEAD:main`). Actif dans tout projet qui a une config greenlyt.
- **Kill switch** : crée le fichier `.greenlyt/STOP` ou exporte `GREENLYT_DISABLED=1`. Le run est marqué `aborted` et la boucle s'arrête.

## Prérequis

`bash`, `git`, `jq`, plus `gh` (GitHub) ou `az` avec l'extension `azure-devops` (Azure DevOps), authentifiés.

## Développement

```bash
bash tests/unit/run.sh          # tests unitaires des hooks et de la CLI (bash pur), lancés en CI à chaque push
claude plugin validate .        # validation du plugin et de la marketplace
bash tests/e2e/run.sh js budget # e2e : fixtures js | php-phpunit, scénarios success | budget
```

Les e2e consomment de vrais appels au modèle (`ANTHROPIC_API_KEY`) : ils sont lancés à la main ou en nightly, jamais à chaque push. La forge y est simulée (`GREENLYT_FORGE_DRY_RUN=1`) et le remote est un repo git bare local.

## Versionnage

Semver par tags git `vX.Y.Z`. La version de `.claude-plugin/plugin.json` et de `.claude-plugin/marketplace.json` doit correspondre au tag, et le `CHANGELOG.md` doit contenir la section de la version : la CI le vérifie à chaque tag.
