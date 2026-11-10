# Changelog

Toutes les évolutions notables de ce projet sont consignées ici.

Le format suit [Keep a Changelog](https://keepachangelog.com/fr/1.1.0/) et le projet respecte le [versionnage sémantique](https://semver.org/lang/fr/).

## [Unreleased]

## [0.1.0] - 2026-11-10

### Ajouté

- Skill `/greenlyt:init` : création de `.greenlyt/config.json` (commande de test, forge, branches protégées, plafond).
- Skill `/greenlyt:spec` : rédaction, stockage et validation d'une spec à critères d'acceptation vérifiables, mode mise à jour après échec.
- Skill `/greenlyt:run` : boucle développeur ↔ relecteur jusqu'à des tests verts et un verdict approuvé, PR draft GitHub ou Azure DevOps, rapport d'échec avec questions ouvertes, reprise d'un run.
- Agents `implementer` et `reviewer`.
- Hook `Stop` (plafond, `stop_hook_active`, kill switch) et hook `PreToolUse` de garde des branches protégées.
- CLI `bin/greenlyt` : état de run, exécution des tests, verdict, préflight, rapports, PR.
- Tests unitaires en bash pur, fixtures PHP/PHPUnit et JS, scénarios e2e, CI.
