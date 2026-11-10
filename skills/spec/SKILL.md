---
name: spec
description: Rédige et stocke la spec d'une évolution avant toute implémentation greenlyt — critères d'acceptation numérotés et vérifiables, périmètre inclus/exclu, ancrage dans la codebase — puis la fait valider par l'utilisateur. Sert aussi à mettre à jour une spec après un échec de /greenlyt:run. Déclencher sur /greenlyt:spec, « rédige la spec greenlyt », « spécifie ce besoin pour greenlyt », « mets à jour la spec <slug> ».
argument-hint: "\"<besoin en texte libre>\" | <slug existant>"
---

# /greenlyt:spec

Produit la spec qui servira de **référence fixe** à la boucle : le développeur l'implémente, le relecteur s'en sert pour juger et pour repérer les libertés. Une spec floue donne une boucle qui ne converge pas : la précision ici est la priorité.

## 1. Préconditions

- `.greenlyt/config.json` existe. Sinon, renvoie vers `/greenlyt:init` et arrête-toi.
- Lis `docsDir` dans la config (par défaut `docs/greenlyt`). Les specs vivent dans `<docsDir>/specs/<slug>.md`.

## 2. Mode

- **Argument = slug d'une spec existante** → mode **mise à jour**. Lis la spec et, s'il existe, le dernier rapport d'échec `<docsDir>/runs/*-<slug>.md` : ses « Questions ouvertes » sont le point de départ.
- **Sinon** → mode **création**. Propose un slug en kebab-case court (ex. `export-csv-dossiers`) et vérifie qu'il n'existe pas déjà.

## 3. Ancrage dans le code

Avant de rédiger, explore la codebase : où la fonctionnalité s'insère, le comportement actuel, les conventions et les tests existants. Lis le `CLAUDE.md` du repo s'il existe. Ne présume rien que tu n'as pas lu.

## 4. Clarification

Pose les questions nécessaires pour lever les ambiguïtés, **une à la fois**, en commençant par celle qui change le plus le résultat. En mode mise à jour, commence par les questions ouvertes du rapport d'échec.

## 5. Rédaction

Remplis `templates/spec.md` (dans le dossier de ce skill). Exigences :

- Chaque critère est numéroté `AC-n`, formulé de façon **vérifiable par un test automatisé** (entrée, action, résultat observable).
- Le périmètre **exclu** est explicite : c'est ce qui permet au relecteur de qualifier une liberté.
- Aucune question ouverte bloquante ne reste à la validation.
- La ligne `Statut : brouillon` reste telle quelle tant que l'utilisateur n'a pas validé.

Écris le fichier `<docsDir>/specs/<slug>.md` et montre-le à l'utilisateur.

## 6. Validation

Demande explicitement : « Valides-tu cette spec ? ». Itère sur ses retours. **Seulement** après un accord explicite, remplace la ligne par `Statut : validée`. Ne commite pas : `/greenlyt:run` commite la spec en premier commit de la branche de travail.

Indique la suite : `/greenlyt:run <slug>`.
