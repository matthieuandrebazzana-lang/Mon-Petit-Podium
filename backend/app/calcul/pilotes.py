"""Grille des pilotes — le pont entre les numéros OpenF1 et les libellés Unibet.

Ce module existe parce que les deux sources ne parlent pas la même langue :

- **Unibet** nomme ses issues avec un libellé de pilote (« AK.Antonelli »,
  « C.Sainz Jr ») et un identifiant d'issue (`o701093319`) qui change à chaque
  Grand Prix ;
- **OpenF1** ne connaît que le `driver_number` (12, 55), et ne dit rien d'Unibet.

Le rapprochement se fait donc par le nom, et il est fait dans
`app/calcul/points.py` — jamais ici. Ce module ne fournit que **la matière** :
qui court en 2026, sous quel numéro, et sous quels libellés Unibet l'écrit.

Deux usages, et le second est celui qui a motivé le module :

1. **Compléter le rapprochement de noms.** Cinq clés sont dérivées
   automatiquement de chaque pilote OpenF1 (nom complet, nom de famille,
   acronyme, initiale + nom, prénom + nom). Elles couvrent la grande majorité
   des libellés Unibet, mais pas tous : OpenF1 écrit « Kimi Antonelli » là où
   Unibet écrit « AK.Antonelli » (Andrea Kimi), et « Carlos Sainz » là où Unibet
   écrit « C.Sainz Jr ». Ces écarts sont irréductibles par une règle : ils sont
   donc listés un par un, en `alias`.

2. **Fabriquer un index de pilotes sans appeler OpenF1**, pour le banc d'essai
   `POST /jobs/resultats/{gp_id}/test` : injecter des résultats fictifs suppose
   de savoir qui porte le numéro 12, et l'API n'a rien à en dire avant la course.

> **À mettre à jour à chaque saison.** Les numéros changent (un champion peut
> prendre le 1), les pilotes aussi. Une table périmée ne fait pas de dégât
> silencieux : `alias_unibet()` vérifie que le nom de famille du numéro demandé
> est bien celui de la table avant de rendre quoi que ce soit, et un pilote
> absent laisse simplement le pronostic non validé (`points_gagnes = NULL`) au
> lieu d'être attribué au mauvais.

Les libellés Unibet ci-dessous ont été relevés sur les vraies cotes du GP Pays
Bas 2026 (22 pilotes, marchés « Vainqueur » et « Podium »), les numéros et
écuries sur `/drivers` d'OpenF1 pour la même saison.
"""

from dataclasses import dataclass, field

# Saison décrite par la table. Sert aux messages de journal : voir « 2026 » dans
# un log de 2027 dit immédiatement ce qu'il y a à corriger.
SAISON = 2026


@dataclass(frozen=True)
class Pilote:
    """Un pilote de la grille, tel qu'OpenF1 le nomme et tel qu'Unibet l'écrit."""

    numero: int
    prenom: str
    nom_famille: str
    acronyme: str
    equipe: str
    # Libellés Unibet que les cinq clés dérivées ne retrouvent pas. Vide pour la
    # quasi-totalité de la grille : n'y mettre que ce qui manque réellement,
    # une liste qui grossit sans raison finirait par créer des ambiguïtés.
    alias: tuple[str, ...] = field(default=())

    @property
    def nom(self) -> str:
        """Le nom complet dans la forme d'OpenF1 : « Kimi ANTONELLI »."""
        return f"{self.prenom} {self.nom_famille.upper()}"


# Grille 2026. Les écuries sont écrites **comme OpenF1 les écrit** (« Red Bull
# Racing », « Haas F1 Team ») : c'est cette forme que le marché « Ecurie
# Vainqueur » doit retrouver, et `points.equipe_du_libelle` sait déjà ramener
# « Red Bull » et « Haas » sur elle.
GRILLE: tuple[Pilote, ...] = (
    Pilote(1, "Lando", "Norris", "NOR", "McLaren"),
    Pilote(3, "Max", "Verstappen", "VER", "Red Bull Racing"),
    Pilote(5, "Gabriel", "Bortoleto", "BOR", "Audi"),
    Pilote(6, "Isack", "Hadjar", "HAD", "Red Bull Racing"),
    Pilote(10, "Pierre", "Gasly", "GAS", "Alpine"),
    Pilote(11, "Sergio", "Perez", "PER", "Cadillac"),
    # OpenF1 abrège son prénom en « Kimi », Unibet garde les deux initiales de
    # « Andrea Kimi ». Sans cet alias, le favori du GP (28 pts) ne serait
    # rapproché d'aucun pilote et tous ses pronostics resteraient à NULL.
    Pilote(12, "Kimi", "Antonelli", "ANT", "Mercedes", ("AK.Antonelli", "A.Antonelli")),
    Pilote(14, "Fernando", "Alonso", "ALO", "Aston Martin"),
    Pilote(16, "Charles", "Leclerc", "LEC", "Ferrari"),
    Pilote(18, "Lance", "Stroll", "STR", "Aston Martin"),
    Pilote(23, "Alexander", "Albon", "ALB", "Williams"),
    Pilote(27, "Nico", "Hulkenberg", "HUL", "Audi"),
    Pilote(30, "Liam", "Lawson", "LAW", "Racing Bulls"),
    Pilote(31, "Esteban", "Ocon", "OCO", "Haas F1 Team"),
    Pilote(41, "Arvid", "Lindblad", "LIN", "Racing Bulls"),
    Pilote(43, "Franco", "Colapinto", "COL", "Alpine"),
    Pilote(44, "Lewis", "Hamilton", "HAM", "Ferrari"),
    # Unibet suffixe « Jr », OpenF1 non. « csainzjr » ne ressemble à aucune des
    # cinq clés dérivées : sans alias, aucun pronostic sur Sainz ne serait noté.
    Pilote(55, "Carlos", "Sainz", "SAI", "Williams", ("C.Sainz Jr", "Carlos Sainz Jr")),
    Pilote(63, "George", "Russell", "RUS", "Mercedes"),
    Pilote(77, "Valtteri", "Bottas", "BOT", "Cadillac"),
    Pilote(81, "Oscar", "Piastri", "PIA", "McLaren"),
    Pilote(87, "Oliver", "Bearman", "BEA", "Haas F1 Team"),
)

PAR_NUMERO: dict[int, Pilote] = {pilote.numero: pilote for pilote in GRILLE}


def _cle(texte: str) -> str:
    """Normalisation locale, volontairement dupliquée de `points.normaliser`.

    Deux lettres de code plutôt qu'un import : `points` importe ce module pour
    ses alias, l'importer en retour créerait un cycle. La règle est la même des
    deux côtés — minuscules, lettres et chiffres seulement — et le seul usage
    ici est une comparaison de noms de famille sans accent ni casse.
    """
    return "".join(caractere for caractere in texte.lower() if caractere.isalnum())


def alias_unibet(numero: int, nom_famille: str) -> tuple[str, ...]:
    """Les libellés Unibet supplémentaires d'un pilote, ou rien.

    Le **nom de famille est exigé en plus du numéro**, et c'est tout le garde-fou
    de ce module : les numéros sont réattribués d'une saison à l'autre. Si le 12
    n'est plus Antonelli, la table périmée ne collera pas ses alias sur le
    nouveau titulaire — elle ne rendra rien, et le pronostic restera simplement
    non validé, ce qui se voit dans les logs.
    """
    pilote = PAR_NUMERO.get(numero)
    if pilote is None or not pilote.alias:
        return ()
    if _cle(pilote.nom_famille) != _cle(nom_famille or ""):
        return ()
    return pilote.alias


def index_pilotes() -> dict[str, dict]:
    """L'index { numéro → identité }, dans la forme exacte d'OpenF1.

    Reproduit ce que `scraper.openf1._index_pilotes` construit à partir de
    `/drivers`, pour que `calcul.points.analyser` consomme les deux sans savoir
    d'où elles viennent. Les clés sont des **chaînes**, comme dans
    `donnees_brutes->'pilotes'` : un objet JSON n'a pas de clé numérique.
    """
    return {
        str(pilote.numero): {
            "nom": pilote.nom,
            "prenom": pilote.prenom,
            "nom_famille": pilote.nom_famille,
            "acronyme": pilote.acronyme,
            "equipe": pilote.equipe,
        }
        for pilote in GRILLE
    }
