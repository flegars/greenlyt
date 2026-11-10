# Multiplication dans la calculatrice

Statut : validée

## Contexte

La calculatrice du projet expose uniquement l'addition.

## Objectif

Ajouter la multiplication de deux entiers.

## Périmètre

### Inclus

- Une fonction (JS : `multiply(a, b)` exportée par `src/calculator.js`) ou une méthode (PHP : `Calculator::multiply(int $a, int $b): int`) qui multiplie deux entiers.

### Exclu

- Toute autre opération, toute validation d'entrée, toute modification de l'addition.

## Critères d'acceptation

- **AC-1** — Étant donnés 3 et 4, quand on les multiplie, alors le résultat est 12.
- **AC-2** — Étant donnés -2 et 5, quand on les multiplie, alors le résultat est -10.
- **AC-3** — L'addition existante reste inchangée et son test passe toujours.

## Contraintes

- Aucune dépendance supplémentaire.

## Questions ouvertes

- Aucune.
