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

import unicodedata
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
    # Code de nationalité, clé de `NATIONALITES`. Il vit ICI et non dans les
    # données OpenF1 : `country_code` de `/drivers` est déprécié et disparaît
    # fin 2026 (`scraper.md` §9). Le marché « nationalité du vainqueur » ne peut
    # donc dépendre que d'une table statique, et c'est celle-ci.
    nationalite: str = ""
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
    Pilote(1, "Lando", "Norris", "NOR", "McLaren", "GBR"),
    Pilote(3, "Max", "Verstappen", "VER", "Red Bull Racing", "NED"),
    Pilote(5, "Gabriel", "Bortoleto", "BOR", "Audi", "BRA"),
    Pilote(6, "Isack", "Hadjar", "HAD", "Red Bull Racing", "FRA"),
    Pilote(10, "Pierre", "Gasly", "GAS", "Alpine", "FRA"),
    Pilote(11, "Sergio", "Perez", "PER", "Cadillac", "MEX"),
    # OpenF1 abrège son prénom en « Kimi », Unibet garde les deux initiales de
    # « Andrea Kimi ». Sans cet alias, le favori du GP (28 pts) ne serait
    # rapproché d'aucun pilote et tous ses pronostics resteraient à NULL.
    Pilote(
        12, "Kimi", "Antonelli", "ANT", "Mercedes", "ITA",
        alias=("AK.Antonelli", "A.Antonelli"),
    ),
    Pilote(14, "Fernando", "Alonso", "ALO", "Aston Martin", "ESP"),
    Pilote(16, "Charles", "Leclerc", "LEC", "Ferrari", "MON"),
    Pilote(18, "Lance", "Stroll", "STR", "Aston Martin", "CAN"),
    Pilote(23, "Alexander", "Albon", "ALB", "Williams", "THA"),
    Pilote(27, "Nico", "Hulkenberg", "HUL", "Audi", "GER"),
    Pilote(30, "Liam", "Lawson", "LAW", "Racing Bulls", "NZL"),
    Pilote(31, "Esteban", "Ocon", "OCO", "Haas F1 Team", "FRA"),
    Pilote(41, "Arvid", "Lindblad", "LIN", "Racing Bulls", "GBR"),
    Pilote(43, "Franco", "Colapinto", "COL", "Alpine", "ARG"),
    Pilote(44, "Lewis", "Hamilton", "HAM", "Ferrari", "GBR"),
    # Unibet suffixe « Jr », OpenF1 non. « csainzjr » ne ressemble à aucune des
    # cinq clés dérivées : sans alias, aucun pronostic sur Sainz ne serait noté.
    Pilote(
        55, "Carlos", "Sainz", "SAI", "Williams", "ESP",
        alias=("C.Sainz Jr", "Carlos Sainz Jr"),
    ),
    Pilote(63, "George", "Russell", "RUS", "Mercedes", "GBR"),
    Pilote(77, "Valtteri", "Bottas", "BOT", "Cadillac", "FIN"),
    Pilote(81, "Oscar", "Piastri", "PIA", "McLaren", "AUS"),
    Pilote(87, "Oliver", "Bearman", "BEA", "Haas F1 Team", "GBR"),
)


# Les libellés sous lesquels Unibet peut écrire une nationalité, par code. Le
# marché « nationalité du vainqueur » ne propose ni un pilote ni un oui/non :
# son issue est un **peuple ou un pays**, et rien ne dit lequel des deux Unibet
# écrit. Les deux formes sont donc acceptées, plus les variantes courantes.
#
# **Rien n'est dérivé par règle.** Un pluriel obtenu en ajoutant « s » ferait de
# « Pays-Bas » un « Pays-Ba », et une règle de féminin ferait de « Français » un
# « Française » qui existe déjà. Chaque forme est écrite parce qu'elle est
# plausible sous la plume d'Unibet, jamais parce qu'un algorithme la produit.
#
# **Aucun libellé n'a été confronté à un vrai marché Unibet** — comme les sept
# autres familles de `metier.md` §4. Une issue non reconnue est journalisée en
# toutes lettres et laisse le pronostic à `NULL`, jamais à `0` : c'est cette
# ligne de journal qu'il faudra chercher après le premier vrai marché.
NATIONALITES: dict[str, tuple[str, ...]] = {
    "GBR": ("Britannique", "Britanniques", "Royaume-Uni", "Grande-Bretagne",
            "Anglais", "Anglaise", "Angleterre"),
    "NED": ("Néerlandais", "Néerlandaise", "Pays-Bas", "Hollandais", "Hollande"),
    "BRA": ("Brésilien", "Brésilienne", "Brésil"),
    "FRA": ("Français", "Française", "France"),
    "MEX": ("Mexicain", "Mexicaine", "Mexique"),
    "ITA": ("Italien", "Italienne", "Italie"),
    "ESP": ("Espagnol", "Espagnole", "Espagne"),
    "MON": ("Monégasque", "Monaco"),
    "CAN": ("Canadien", "Canadienne", "Canada"),
    "THA": ("Thaïlandais", "Thaïlandaise", "Thaïlande", "Thaï"),
    "GER": ("Allemand", "Allemande", "Allemagne"),
    "NZL": ("Néo-Zélandais", "Néo-Zélandaise", "Nouvelle-Zélande"),
    "ARG": ("Argentin", "Argentine", "Argentinien"),
    "FIN": ("Finlandais", "Finlandaise", "Finlande"),
    "AUS": ("Australien", "Australienne", "Australie"),
}


PAR_NUMERO: dict[int, Pilote] = {pilote.numero: pilote for pilote in GRILLE}


def _cle(texte: str) -> str:
    """Normalisation locale, volontairement dupliquée de `points.normaliser`.

    Deux lettres de code plutôt qu'un import : `points` importe ce module pour
    ses alias, l'importer en retour créerait un cycle. La règle est la même des
    deux côtés — minuscules, lettres et chiffres seulement — et le seul usage
    ici est une comparaison de noms de famille sans accent ni casse.
    """
    return "".join(caractere for caractere in texte.lower() if caractere.isalnum())


def _cle_nationalite(texte: str) -> str:
    """Réduit un libellé de nationalité à ses lettres, accents et tirets ôtés.

    « Néo-Zélandais », « neo zelandais » et « NÉOZÉLANDAIS » se ramènent tous à
    « neozelandais ». Les accents passent par `unicodedata` et non par une table
    de substitution : « é » et « ï » n'ont pas à être énumérés.
    """
    sans_accents = "".join(
        caractere
        for caractere in unicodedata.normalize("NFD", texte or "")
        if unicodedata.category(caractere) != "Mn"
    )
    return "".join(c for c in sans_accents.lower() if c.isalnum())


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


def _indexer_nationalites() -> dict[str, str]:
    """Index inverse { libellé normalisé → code }, construit une fois.

    Une forme revendiquée par **deux** nationalités est retirée plutôt
    qu'attribuée à la première venue — exactement comme une clé de nom ambiguë
    dans `points._indexer_pilotes`. Mieux vaut ne pas juger un pronostic que le
    juger sur la mauvaise nationalité. Le cas n'existe pas dans la table
    d'aujourd'hui ; il n'a pas à être découvert le jour où quelqu'un ajoute une
    quinzième entrée.
    """
    index: dict[str, str] = {}
    ambigus: set[str] = set()
    for code, libelles in NATIONALITES.items():
        for libelle in libelles:
            cle = _cle_nationalite(libelle)
            if not cle:
                continue
            if index.get(cle, code) != code:
                ambigus.add(cle)
            index[cle] = code
    for cle in ambigus:
        del index[cle]
    return index


_PAR_LIBELLE: dict[str, str] = _indexer_nationalites()


def code_nationalite(libelle: str) -> str | None:
    """Le code de nationalité derrière un libellé Unibet, ou `None`.

    `None` veut dire « je ne reconnais pas cette issue » — pas « aucun pilote
    n'a cette nationalité ». L'appelant laisse alors le pronostic à `NULL` et
    journalise le libellé en clair : c'est cette ligne qui dira quelle forme
    ajouter à `NATIONALITES`.
    """
    return _PAR_LIBELLE.get(_cle_nationalite(libelle))


def nationalite_du_pilote(numero: int, nom_famille: str) -> str | None:
    """La nationalité d'un pilote, sous le même garde-fou que `alias_unibet`.

    **Le nom de famille est exigé en plus du numéro**, et pour la raison déjà
    donnée : les numéros sont réattribués d'une saison à l'autre. Une table
    périmée qui croirait encore le 12 italien ne dira rien du tout plutôt que de
    prêter la nationalité d'Antonelli à son successeur — le pronostic reste non
    validé, ce qui se voit dans les logs et se rattrape.
    """
    pilote = PAR_NUMERO.get(numero)
    if pilote is None or not pilote.nationalite:
        return None
    if _cle(pilote.nom_famille) != _cle(nom_famille or ""):
        return None
    return pilote.nationalite


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
