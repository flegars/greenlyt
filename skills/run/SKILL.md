---
name: run
description: Lance la boucle greenlyt sur une spec validée — un agent développeur implémente, un agent relecteur indépendant le challenge, tour après tour, jusqu'à des tests réellement verts et un verdict approuvé — puis ouvre une PR draft sur GitHub ou Azure DevOps. Signale les libertés prises hors spec et s'arrête avec un rapport d'échec et des questions ouvertes si le plafond de tentatives est atteint. Reprend un run en attente ou en échec. Déclencher sur /greenlyt:run, « lance la boucle greenlyt sur <slug> », « implémente la spec <slug> avec greenlyt ».
argument-hint: "<slug de la spec>"
---

# /greenlyt:run

Orchestre la boucle. **Toute** opération sur l'état, les tests, git et la forge passe par la CLI du plugin. Tu ne modifies jamais `.greenlyt/state/` à la main, et tu ne déclares jamais un résultat que la CLI n'a pas constaté.

```
GL="${CLAUDE_PLUGIN_ROOT}/bin/greenlyt"
```

Un hook `Stop` t'empêche de t'arrêter tant que le run est `running` et que le plafond n'est pas atteint. Si le kill switch est activé (`.greenlyt/STOP` ou `GREENLYT_DISABLED=1`), arrête-toi immédiatement : vérifie-le avec `test -f .greenlyt/STOP` avant chaque étape de la boucle et, s'il est présent, exécute `"$GL" state set-status <run-id> aborted` puis rends la main.

## 1. Démarrage

L'argument est le slug. La spec est `<docsDir>/specs/<slug>.md`, où `docsDir` vient de `"$GL" config .docsDir`.

1. `run_id=$("$GL" state find <slug>)` :
   - **trouvé, statut `waiting`** : exécute `git checkout <branch du run>`, puis va directement à l'étape 3.1 (décision sur les libertés).
   - **trouvé, statut `failed`** : exécute `git checkout <branch du run>`. Vérifie que la spec porte `Statut : validée` ; sinon renvoie vers `/greenlyt:spec <slug>` et arrête-toi. Si la spec a été modifiée, commite-la (`git add <spec> && git commit -m "docs(greenlyt): spec <slug> mise à jour"`). Puis `"$GL" state rebudget <run_id>` et va à l'étape 2.
2. Sinon, `run_id=$("$GL" preflight <docsDir>/specs/<slug>.md)`. En cas d'échec, explique le code à l'utilisateur et arrête-toi :

| Code | Signification |
|---|---|
| 10 | config absente ou sans `testCommand` → `/greenlyt:init` |
| 11 | kill switch actif |
| 12 | spec absente ou non validée → `/greenlyt:spec` |
| 13 | arbre de travail non propre → commiter ou remiser |
| 14 | un autre run est déjà en cours |
| 15 | la suite de tests échoue déjà sur la branche de base |
| 16 | la branche de travail existe déjà |

Annonce le run : run-id, branche, plafond.

## 2. Boucle

Répète :

1. `attempt=$("$GL" state next-attempt <run_id>)`. **Code 3** (plafond atteint) → étape 4.
2. **Développeur** : lance l'agent `greenlyt:implementer` avec :
   - le chemin de la spec, le tour `attempt` / `maxAttempts` ;
   - à partir du tour 2 : les objections du verdict précédent (`"$GL" state get <run_id> .verdict.objections`), la sortie des tests (`"$GL" state get <run_id> .tests.tail`) ;
   - les libertés que l'utilisateur a demandé de retirer, s'il y en a.
3. **Tests** : `"$GL" test <run_id>`. Le code de sortie enregistré est le seul qui fait foi.
4. **Relecteur** : lance l'agent `greenlyt:reviewer` avec le chemin de la spec, la `baseBranch`, le code de sortie et la sortie des tests (lus dans l'état), et le résumé du développeur.
5. **Verdict** : extrais le bloc JSON de la réponse du relecteur, écris-le dans `.greenlyt/state/<run_id>.verdict`, puis `"$GL" verdict <run_id> .greenlyt/state/<run_id>.verdict`. Si la CLI le refuse (format invalide), relance le relecteur une fois en lui donnant l'erreur ; au second refus, enregistre un verdict `{"approved": false, "objections": [{"ref": "qualité", "detail": "verdict du relecteur illisible"}], "deviations": [], "specIssues": []}`.
6. `"$GL" commit-tour <run_id>`.
7. `"$GL" decide <run_id>` :
   - `retry` → résume le tour en une ligne (tests, objections) et recommence en 2.1 ;
   - `exhausted` → étape 4 ;
   - `success` → étape 3.

## 3. Succès

### 3.1 Libertés

Lis `"$GL" state get <run_id> .verdict.deviations` et la config `deviations`.

- **Aucune liberté**, ou `deviations: "report"` → 3.2.
- Sinon (`ask`) : `"$GL" state set-status <run_id> waiting`, puis présente chaque liberté (description, fichiers, justification) et demande à l'utilisateur avec `AskUserQuestion` : **accepter** toutes les libertés, ou **corriger** (préciser lesquelles retirer).
  - **Accepter** → `"$GL" state set-status <run_id> running` puis 3.2.
  - **Corriger** : si `attempt < maxAttempts` → `"$GL" state set-status <run_id> running` et retour en 2.1, en transmettant ces libertés au développeur comme à retirer. Sinon → étape 4 (le run échoue : jamais de PR avec une liberté refusée).

### 3.2 Rapport et PR

1. `report=$("$GL" report <run_id> success)`, puis `git add "$report" && git commit -m "docs(greenlyt): rapport <run_id>"`.
2. Écris dans `.greenlyt/state/<run_id>.acceptance.md` le tableau Markdown **AC → preuve** (une ligne par critère de la spec : `| AC-n | test(s) | fichier(s) |`), construit à partir de la spec et du dernier résumé du développeur, vérifié contre le diff.
3. `body=$("$GL" report <run_id> pr .greenlyt/state/<run_id>.acceptance.md)`.
4. `url=$("$GL" pr <run_id> "$body")`.
5. `"$GL" state set-status <run_id> succeeded`.
6. Donne à l'utilisateur : l'URL de la PR draft, le nombre de tours, les libertés acceptées, le chemin du rapport.

## 4. Échec

1. `report=$("$GL" report <run_id> failure)`. Ne le commite pas, ne pousse rien.
2. `"$GL" state set-status <run_id> failed`.
3. Présente à l'utilisateur : le chemin du rapport, les tests encore rouges, les objections non résolues et **les questions ouvertes** (`specIssues`). S'il n'y en a aucune, formule toi-même les questions qui permettraient de recentrer la spec au vu des objections récurrentes.
4. Propose la suite : `/greenlyt:spec <slug>` pour mettre la spec à jour avec ses réponses, puis `/greenlyt:run <slug>` pour relancer la boucle avec un budget neuf sur la même branche.
