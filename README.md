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
