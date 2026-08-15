import '../../../data/models/recipe.dart';
import '../../../data/models/weekly_plan.dart';
import '../../../l10n/gen/app_localizations.dart';

/// Enum-to-label mapping, in one place.
///
/// The generated localisations expose one getter per key rather than a lookup
/// by name, so these switches are the price of not shipping untranslated enum
/// names into the UI. Keeping them together means a new region or unit fails to
/// compile in exactly one file.

String regionLabel(AppLocalizations l10n, Region region) => switch (region) {
  Region.baghdadi => l10n.regionBaghdadi,
  Region.mosuli => l10n.regionMosuli,
  Region.basrawi => l10n.regionBasrawi,
  Region.anbari => l10n.regionAnbari,
  Region.kurdishErbil => l10n.regionKurdishErbil,
  Region.kurdishSulaymaniyah => l10n.regionKurdishSulaymaniyah,
  Region.kurdishDuhok => l10n.regionKurdishDuhok,
  Region.turkmenKirkuk => l10n.regionTurkmenKirkuk,
  Region.general => l10n.regionGeneral,
};

String difficultyLabel(AppLocalizations l10n, Difficulty difficulty) =>
    switch (difficulty) {
      Difficulty.easy => l10n.difficultyEasy,
      Difficulty.medium => l10n.difficultyMedium,
      Difficulty.hard => l10n.difficultyHard,
    };

String costBandLabel(AppLocalizations l10n, CostBand band) => switch (band) {
  CostBand.cheap => l10n.costCheap,
  CostBand.medium => l10n.costMedium,
  CostBand.occasion => l10n.costOccasion,
};

/// Local measures come first in the picker because they are what people
/// actually say in an Iraqi kitchen. Grams exist for the ones who want them.
String unitLabel(AppLocalizations l10n, Unit unit) => switch (unit) {
  Unit.istikan => l10n.unitIstikan,
  Unit.finjan => l10n.unitFinjan,
  Unit.cup => l10n.unitCup,
  Unit.tablespoon => l10n.unitTablespoon,
  Unit.teaspoon => l10n.unitTeaspoon,
  Unit.gram => l10n.unitGram,
  Unit.kilo => l10n.unitKilo,
  Unit.ml => l10n.unitMl,
  Unit.litre => l10n.unitLitre,
  Unit.piece => l10n.unitPiece,
  Unit.pinch => l10n.unitPinch,
  Unit.toTaste => l10n.unitToTaste,
};

String mealTypeLabel(AppLocalizations l10n, MealType type) => switch (type) {
  MealType.lunch => l10n.mealLunch,
  MealType.dinner => l10n.mealDinner,
  MealType.breakfast => l10n.mealBreakfast,
  MealType.suhoor => l10n.mealSuhoor,
  MealType.iftar => l10n.mealIftar,
};
