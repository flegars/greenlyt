---
name: init
description: Initialise greenlyt dans le projet courant en créant .greenlyt/config.json (commande de test, forge GitHub ou Azure DevOps, branches protégées, plafond de tentatives, dossier de docs). À lancer une fois par projet, avant /greenlyt:spec et /greenlyt:run. Déclencher sur /greenlyt:init, « initialise greenlyt », « configure greenlyt pour ce projet ».
argument-hint: "(aucun argument)"
---

# /greenlyt:init

Crée la configuration greenlyt du projet courant. Rien n'est écrit avant que l'utilisateur ait validé la proposition.

## 1. Préconditions

- Le répertoire courant est dans un repo git (`git rev-parse --show-toplevel`). Sinon, arrête-toi et dis-le.
- Si `.greenlyt/config.json` existe déjà, affiche-le et demande si l'utilisateur veut le modifier ou s'arrêter là.

## 2. Détection

Depuis la racine du repo :

| Indice | Proposition de `testCommand` |
|---|---|
| `composer.json` + `vendor/bin/phpunit` ou `phpunit.xml(.dist)` | `vendor/bin/phpunit` |
| `package.json` avec un script `test` | `npm test` (ou `pnpm test` / `yarn test` selon le lockfile présent) |
| Autre | demande à l'utilisateur |

Forge, depuis `git remote get-url origin` :

- `github.com` → `{"type": "github"}`
- `dev.azure.com/<org>/<project>/_git/<repo>` ou `<org>.visualstudio.com/<project>/_git/<repo>` → `{"type": "azure-devops", "organization": "https://dev.azure.com/<org>", "project": "<project>", "repository": "<repo>"}`
- Autre ou pas de remote → demande à l'utilisateur.

`baseBranch` : la branche par défaut du remote (`git symbolic-ref refs/remotes/origin/HEAD`), sinon `main`.

## 3. Proposition

Présente la config complète, valeurs par défaut comprises :

```json
{
  "docsDir": "docs/greenlyt",
  "testCommand": "<détecté>",
  "maxAttempts": 5,
  "protectedBranches": ["main", "master", "develop"],
  "branchPrefix": "greenlyt/",
  "deviations": "ask",
  "forge": { "type": "<détecté>", "remote": "origin", "baseBranch": "<détecté>" }
}
```

Explique en une ligne chacune des valeurs que l'utilisateur pourrait vouloir changer : `docsDir`, `maxAttempts`, `deviations` (`ask` = s'arrêter pour faire trancher les libertés, `report` = seulement les lister dans la PR). Demande validation.

## 4. Écriture

Après accord explicite :

1. Écris `.greenlyt/config.json`.
2. Ajoute `.greenlyt/state/` au `.gitignore` du projet s'il n'y est pas.
3. Vérifie que la commande de test passe : `bash -c "<testCommand>"`. Si elle échoue, préviens que `/greenlyt:run` refusera de démarrer tant qu'elle n'est pas verte.
4. Rappelle de commiter `.greenlyt/config.json` et `.gitignore` : `/greenlyt:run` exige un arbre de travail propre.
5. Indique la suite : `/greenlyt:spec "<besoin>"`.
