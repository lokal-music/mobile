// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Russian (`ru`).
class AppLocalizationsRu extends AppLocalizations {
  AppLocalizationsRu([String locale = 'ru']) : super(locale);

  @override
  String get aNewerFlickBuildIsOn =>
      'В Play Store доступна более новая сборка Lokal.';

  @override
  String get aPlaylistWithThisNameAlready =>
      'Плейлист с таким названием уже существует';

  @override
  String get aSmoothContinuousWaveAcrossFrequencies =>
      'Плавная непрерывная волна по всему спектру частот';

  @override
  String get aSongWithALongTitle =>
      'Трек с длинным названием для предпросмотра';

  @override
  String get aTighterMixOfFavoritesAnd =>
      'Более плотная подборка из любимых треков и песен, к которым вы постоянно возвращаетесь.';

  @override
  String get aWeekAndCountingYourDedication =>
      'Уже неделя подряд — отличная преданность музыке!';

  @override
  String get aaudio => 'AAudio';

  @override
  String get aaudioAndroid81 => 'AAudio (Android 8.1+)';

  @override
  String get aaudioWithOpenslEsFallbackDefault =>
      'AAudio с резервом OpenSL ES (по умолчанию)';

  @override
  String get about => 'О приложении';

  @override
  String get aboutThisAlbum => 'Об этом альбоме';

  @override
  String get absoluteVolumeSync => 'Синхронизация абсолютной громкости';

  @override
  String get accentColor => 'Акцентный цвет';

  @override
  String get accuraterip => 'AccurateRip';

  @override
  String achieved(Object arg1) {
    return 'Получено $arg1';
  }

  @override
  String get achievementUnlocked => 'ДОСТИЖЕНИЕ РАЗБЛОКИРОВАНО';

  @override
  String get activateFallback => 'Включить резервный режим';

  @override
  String get active => 'Активно';

  @override
  String activeBands(Object activeCount) {
    return 'Активных полос: $activeCount';
  }

  @override
  String get activeDays => 'Активные дни';

  @override
  String get add => 'Добавить';

  @override
  String get addAMusicFolderInSettings =>
      'Добавьте папку с музыкой в настройках';

  @override
  String get addANextTrackButton => 'Добавить кнопку следующего трека';

  @override
  String get addAPreviousTrackButton => 'Добавить кнопку предыдущего трека';

  @override
  String get addAtLeastOneLyricLine =>
      'Сначала добавьте хотя бы одну строку текста.';

  @override
  String get addDescription => 'Добавить описание';

  @override
  String get addDescription2 => 'Добавить описание';

  @override
  String get addMusicFoldersInSettings =>
      'Добавьте папки с музыкой в настройках';

  @override
  String get addMusicWithAlbumTagsTo =>
      'Добавьте музыку с тегами альбомов, чтобы увидеть их здесь';

  @override
  String get addMusicWithArtistTagsTo =>
      'Добавьте музыку с тегами исполнителей, чтобы увидеть их здесь';

  @override
  String get addServer => 'Добавить сервер';

  @override
  String get addSongsFromThePlayerMenu => 'Добавляйте треки из меню плеера';

  @override
  String get addSongsFromThePlayerOr =>
      'Добавляйте треки из меню плеера или контекстного меню трека.';

  @override
  String addSongsToPlaylist(Object arg1) {
    return 'Добавить треки ($arg1) в плейлист';
  }

  @override
  String addSongsToPlaylist2(Object arg1) {
    return 'Добавить треки ($arg1) в плейлист';
  }

  @override
  String get addToFavorites => 'Добавить в избранное';

  @override
  String get addToFavorites2 => 'Добавить в избранное';

  @override
  String get addToPlaylist => 'Добавить в плейлист';

  @override
  String get addToPlaylist2 => 'Добавить в плейлист';

  @override
  String get addToQueue => 'Добавить в очередь';

  @override
  String get addToQueue2 => 'Добавить в очередь';

  @override
  String addedSongsTo(Object arg1, Object arg2) {
    return 'В «$arg2» добавлено треков: $arg1';
  }

  @override
  String addedSongsTo2(Object arg1, Object playlistName) {
    return 'В «$playlistName» добавлено треков: $arg1';
  }

  @override
  String addedSongsToFavorites(Object arg1) {
    return 'В избранное добавлено треков: $arg1';
  }

  @override
  String addedSongsToFavorites3(Object arg1) {
    return 'В избранное добавлено треков: $arg1';
  }

  @override
  String addedSongsToQueue(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Добавлено $count треков в очередь',
      many: 'Добавлено $count треков в очередь',
      few: 'Добавлено $count трека в очередь',
      one: 'Добавлено в очередь',
    );
    return '$_temp0';
  }

  @override
  String addedTo(Object arg1) {
    return 'Добавлено в «$arg1»';
  }

  @override
  String addedTo2(Object arg1) {
    return 'Добавлено в «$arg1»';
  }

  @override
  String get addedToFavorites => 'Добавлено в избранное';

  @override
  String addedToFavorites2(Object arg1) {
    return '«$arg1» добавлено в избранное';
  }

  @override
  String get addsPreDriveAndCatchesPeaks =>
      'Добавляет предварительное усиление и ограничивает пики на заданном потолке выхода.';

  @override
  String get adjustMetadataTextSizeInArtwork =>
      'Настройте размер текста метаданных в режиме карточки обложки';

  @override
  String get adjustMetadataTextSizeInImmersive =>
      'Настройте размер текста метаданных в иммерсивном режиме';

  @override
  String get adjustTheMiniPlayerSurface => 'Настройте оформление мини-плеера';

  @override
  String get advanceToARandomCategory => 'Переходить к случайной категории';

  @override
  String get advanceToTheNextCategoryAlphabetically =>
      'Переходить к следующей категории по алфавиту';

  @override
  String get advanceToTheNextMostRecently =>
      'Переходить к следующей недавно добавленной категории';

  @override
  String get advanced => 'Дополнительно';

  @override
  String get advancedMode => 'Расширенный режим';

  @override
  String get afterHours => 'После полуночи';

  @override
  String get afterScanningMatchFilesWithMissing =>
      'После сканирования сопоставлять файлы без тегов с Apple Music. Автоматически применяются только точные совпадения.';

  @override
  String get air => 'Воздух';

  @override
  String get alacAudio => 'Аудио ALAC';

  @override
  String alacBit(Object arg1) {
    return 'ALAC $arg1-бит';
  }

  @override
  String get album => 'Альбом';

  @override
  String get albumArt => 'Обложка альбома';

  @override
  String get albumArt2 => 'Обложка альбома';

  @override
  String get albumArtist => 'Исполнитель альбома';

  @override
  String get albumArtists => 'Исполнители альбомов';

  @override
  String get albumArtwork => 'Обложка альбома';

  @override
  String get albumColors => 'Цвета альбома';

  @override
  String get albumCount => 'Количество альбомов';

  @override
  String get albumLimit => 'ЛИМИТ АЛЬБОМОВ';

  @override
  String get albumName => 'Название альбома';

  @override
  String get albumOptions => 'Параметры альбома';

  @override
  String get albums => 'Альбомы';

  @override
  String albums2(Object arg1) {
    return 'Альбомов: $arg1';
  }

  @override
  String albums3(Object _totalAlbums) {
    return 'Альбомов: $_totalAlbums';
  }

  @override
  String get albumsShownPerPage => 'Альбомов на странице';

  @override
  String albumsSongs(Object arg1, Object arg2) {
    return 'Альбомы: $arg1 • Треки: $arg2';
  }

  @override
  String get all => 'Все';

  @override
  String get allArtists => 'Все исполнители';

  @override
  String get allClearNoDuplicates => 'Всё чисто — дубликатов нет';

  @override
  String get allFormats => 'Все форматы';

  @override
  String get allFrequenciesEqually => 'Все частоты равномерно';

  @override
  String get allPass => 'Всепропускающий';

  @override
  String get allResultsAreHiddenByActive =>
      'Все результаты скрыты активными фильтрами.';

  @override
  String get allSongs => 'Все треки';

  @override
  String get allWordsStamped => 'Все слова размечены';

  @override
  String get allowed => 'Разрешено';

  @override
  String get alphabetical => 'По алфавиту';

  @override
  String get alsoRespectsYourSystemTextSize =>
      'Также учитывается системный размер шрифта';

  @override
  String alt(Object arg1) {
    return 'Альт. $arg1';
  }

  @override
  String get amber => 'Янтарный';

  @override
  String get andArtwork => ' и обложку';

  @override
  String andMoreInRotation(Object arg1) {
    return '$arg1 и другие в ротации';
  }

  @override
  String get android => 'Android';

  @override
  String get androidAudioApi => 'Аудио API Android';

  @override
  String get androidBlockedWritingToThisFile =>
      'Android заблокировал запись в этот файл. Удалите и заново добавьте папку в настройках, чтобы выдать доступ на редактирование, затем повторите попытку.';

  @override
  String get androidDeveloperOptionsTheReliableWay =>
      'Параметры разработчика Android — надёжный способ сменить кодек (принудительное переключение в приложении использует скрытый системный API, заблокированный в стандартном Android)';

  @override
  String get androidDockRoute => 'Док-станция Android';

  @override
  String get androidManagedRustPlaybackPathUsing =>
      'Тракт воспроизведения Rust под управлением Android с нативным бэкендом Oboe.';

  @override
  String get androidUsbRoute => 'USB-маршрут Android';

  @override
  String get animationStyle => 'Стиль анимации';

  @override
  String get apiKey => 'API-ключ';

  @override
  String get appTitle => 'Lokal';

  @override
  String get appearance => 'Оформление';

  @override
  String get appleMusicDataUnavailable => 'Данные Apple Music недоступны';

  @override
  String get appleMusicDataUpdated => 'Данные Apple Music обновлены';

  @override
  String get appleMusicLookupFailedCheckYour =>
      'Не удалось выполнить поиск в Apple Music. Проверьте подключение.';

  @override
  String appliedAutoeqFor(Object arg1) {
    return 'Применён профиль AutoEQ для $arg1';
  }

  @override
  String get apply => 'Применить';

  @override
  String apply2(Object arg1) {
    return 'Применить $arg1';
  }

  @override
  String get applySelected => 'Применить выбранное';

  @override
  String applyTo(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count трекам',
      many: '$count трекам',
      few: '$count трекам',
      one: '$count треку',
    );
    return 'Применить к $_temp0';
  }

  @override
  String get applyingNewAudioEngine => 'Применение нового аудиодвижка…';

  @override
  String get apr => 'Апр';

  @override
  String get aptxAdaptive => 'aptX Adaptive';

  @override
  String get aptxHd => 'aptX HD';

  @override
  String get areYouSureYouWantTo =>
      'Вы уверены, что хотите удалить этот плейлист?';

  @override
  String get areYouSureYouWantTo2 =>
      'Вы уверены, что хотите очистить всю историю прослушиваний? Это действие нельзя отменить.';

  @override
  String get areYouSureYouWantTo3 =>
      'Вы уверены, что хотите сбросить все настройки UAC2? Это действие нельзя отменить.';

  @override
  String get artist => 'Исполнитель';

  @override
  String get artistIsNotAvailableForThis =>
      'Исполнитель недоступен для этого трека';

  @override
  String get artistName => 'Имя исполнителя';

  @override
  String artistUnit(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'исполнителей',
      many: 'исполнителей',
      few: 'исполнителя',
      one: 'исполнитель',
    );
    return '$_temp0';
  }

  @override
  String get artists => 'Исполнители';

  @override
  String artists2(Object arg1) {
    return 'Исполнителей: $arg1';
  }

  @override
  String get artistsInRotation => 'Исполнители в ротации';

  @override
  String get artwork => 'Обложка';

  @override
  String get artworkCard => 'Карточка обложки';

  @override
  String get artworkPlacement => 'Расположение обложки';

  @override
  String get artworkPlacement2 => 'Расположение обложки';

  @override
  String get artworkSize => 'Размер обложки';

  @override
  String get artworkSize2 => 'Размер обложки';

  @override
  String get asmrDreams => 'ASMR-сны';

  @override
  String atKhzBit(Object arg1, Object arg2) {
    return ' при $arg1 кГц/$arg2 бит';
  }

  @override
  String get atLeastOneVersionMustStay =>
      'Должна остаться хотя бы одна версия.';

  @override
  String get attack => 'Атака';

  @override
  String get audioFocus => 'Аудиофокус';

  @override
  String get audioFormat => 'Формат аудио';

  @override
  String get audioFormatIsDisabled => 'Формат аудио отключён';

  @override
  String get audioSignalPath => 'Аудиотракт сигнала';

  @override
  String get aug => 'Авг';

  @override
  String get auto => 'Авто';

  @override
  String get autoAdvance => 'Автопереход';

  @override
  String get autoBeMsbDefaultOnlyChange =>
      'Авто — BE-MSB по умолчанию; меняйте только если нативный DSD шипит';

  @override
  String get autoBitPerfectForUsbDacs => 'Авто Bit-perfect для USB DAC';

  @override
  String get autoFill => 'Автозаполнение';

  @override
  String get autoFullView => 'Авторазворачивание';

  @override
  String get autoIdentifyUntaggedAlbums =>
      'Автораспознавание альбомов без тегов';

  @override
  String get autoNativeDsdOnDapsDop =>
      'Авто — нативный DSD на DAP, DoP для USB DAC, иначе PCM';

  @override
  String get autoReconnect => 'Автопереподключение';

  @override
  String get autoShowFullViewAfterInactivity =>
      'Автоматически переходить в полноэкранный вид при бездействии';

  @override
  String get autoU8ByteInterleavedRecommended =>
      'Авто — побайтовое чередование U8 (рекомендуется)';

  @override
  String get autoeqHeadphones => 'Наушники AutoEQ';

  @override
  String get autoeqHeadphones2 => 'Наушники AutoEQ';

  @override
  String get automatic => 'Автоматически';

  @override
  String get availableDevices => 'Доступные устройства';

  @override
  String b(Object arg1) {
    return 'П$arg1';
  }

  @override
  String get back => 'Назад';

  @override
  String get backOnline => 'Снова в сети';

  @override
  String get backToLocker => 'Назад в хранилище';

  @override
  String get backToReplay => 'Назад в Replay';

  @override
  String get backend => 'Бэкенд';

  @override
  String get background => 'Фон';

  @override
  String get backgroundOpacity => 'Непрозрачность фона';

  @override
  String get balance => 'Баланс';

  @override
  String balance2(Object arg1) {
    return 'Баланс $arg1';
  }

  @override
  String get balanceTempoDampFilterDelaysSize =>
      'Баланс, темп, демпфирование, фильтр, задержки, размер, микс и расширение стерео.';

  @override
  String get balancedQualityAndStability =>
      'Сбалансированное качество и стабильность';

  @override
  String get band => 'Полоса';

  @override
  String get bandControls => 'Управление полосами';

  @override
  String get bandEditors => 'Редакторы полос';

  @override
  String get bandPass => 'Полосовой';

  @override
  String bandU2022(Object arg1, Object arg2) {
    return 'Полоса $arg1  •  $arg2';
  }

  @override
  String bands(Object arg1) {
    return 'Полос: $arg1/31';
  }

  @override
  String bandsActive(Object activeCount, Object arg1) {
    return 'Активно полос: $activeCount/$arg1';
  }

  @override
  String bandsAdjusted(Object adjustedBands) {
    return 'Настроено полос: $adjustedBands';
  }

  @override
  String bandsAdjusted2(Object adjustedCount, Object arg1) {
    return 'Настроено полос: $adjustedCount/$arg1';
  }

  @override
  String bandsPreampDb(Object arg1, Object arg2, Object arg3) {
    return 'Полос: $arg1 · предусиление $arg2 дБ · $arg3';
  }

  @override
  String get bars => 'Столбцы';

  @override
  String get bass => 'Басы';

  @override
  String get bassMidTreble => 'Басы, средние и высокие';

  @override
  String get bassTreble => 'Басы + высокие';

  @override
  String battery(Object battery) {
    return 'Заряд $battery%';
  }

  @override
  String get beLsbBigEndianSubslotLsb =>
      'BE-LSB — big-endian субслот, LSB первым';

  @override
  String get beMsbBigEndianSubslotMsb =>
      'BE-MSB — big-endian субслот, MSB первым (по умолчанию)';

  @override
  String get beMsbPackingTheDefaultWire =>
      'Упаковка BE-MSB — стандартный порядок передачи';

  @override
  String get besideTheSong => 'Рядом с треком';

  @override
  String get bigEndian32BitSubslotMsb =>
      '32-битный big-endian субслот, биты MSB-first';

  @override
  String get bigEndianSubslotLsbFirstBit =>
      'Big-endian субслот, биты LSB-first (реверс бит)';

  @override
  String bit(Object depth) {
    return '$depth бит';
  }

  @override
  String get bitDepth => 'Разрядность';

  @override
  String get bitDepth2 => 'Разрядность';

  @override
  String get bitDepths => 'Разрядности';

  @override
  String get bitPerfect => 'BIT-PERFECT';

  @override
  String get bitPerfect2 => 'Bit-perfect';

  @override
  String get bitPerfectCapsule => 'Капсула Bit-perfect';

  @override
  String get bitPerfectDapInternal => 'Bit-perfect (внутренний DAP)';

  @override
  String get bitPerfectDapInternalDisabledSoftware =>
      'Bit-perfect (внутренний DAP) отключён — активны программные эффекты.';

  @override
  String get bitPerfectDapInternalEnabledAll =>
      'Bit-perfect (внутренний DAP) включён — вся обработка DSP в обходе.';

  @override
  String get bitPerfectEnabledParametricEqIs =>
      'Bit-perfect включён — параметрический EQ не работает на прямом USB-тракте. Перезапустите приложение для применения изменений.';

  @override
  String get bitPerfectUsbDac => 'Bit-perfect (USB DAC)';

  @override
  String get bitPerfectUsbDacCouldNot =>
      'Не удалось включить Bit-perfect (USB DAC). Проверьте диагностику USB для выяснения причины.';

  @override
  String bitPerfectUsbDacCouldNot2(Object arg1) {
    return 'Не удалось включить Bit-perfect (USB DAC) для $arg1. Проверьте диагностику USB.';
  }

  @override
  String bitPerfectUsbDacEnabledFor(Object arg1) {
    return 'Bit-perfect (USB DAC) включён для $arg1.';
  }

  @override
  String get bitPerfectVerified => 'Bit-perfect подтверждён';

  @override
  String get bitSubslotsLlRrPer => '16-битные субслоты: LL|RR на кадр';

  @override
  String get bitSubslotsLlllRrrrPer =>
      '32-битные субслоты: LLLL|RRRR на кадр (устаревший)';

  @override
  String get bitrateAdjustsToSignalQuality =>
      'Битрейт подстраивается под качество сигнала';

  @override
  String get blocked => 'Заблокировано';

  @override
  String get blue => 'Синий';

  @override
  String get bluetooth => 'Bluetooth';

  @override
  String get bluetoothCodecInfo => 'Информация о кодеке Bluetooth';

  @override
  String get bluetoothOutput => 'Вывод по Bluetooth';

  @override
  String get boldSaturatedColorsFromAlbumArt =>
      'Яркие насыщенные цвета с обложки альбома.';

  @override
  String get border => 'Рамка';

  @override
  String get bothBitPerfectOptionsAreOff =>
      'Оба параметра Bit-perfect отключены на этом DAP, поэтому стандартный движок недоступен. Вы всё ещё можете использовать Rust через Oboe или изохронный USB.';

  @override
  String get bottom => 'Снизу';

  @override
  String get bouncy => 'Пружинистая';

  @override
  String get browseByArtworkOpenAnyAlbum =>
      'Листайте обложки, открывайте любой альбом и сразу переходите к списку треков.';

  @override
  String get browseYourArtistLibrary =>
      'Просматривайте библиотеку исполнителей';

  @override
  String get browseYourArtistsExploreTheirDiscographies =>
      'Просматривайте исполнителей, изучайте их дискографии и слушайте их треки.';

  @override
  String get buffer => 'Буфер';

  @override
  String build(Object kAppVersion, Object kAppBuild) {
    return '$kAppVersion (сборка $kAppBuild)';
  }

  @override
  String get buildingYourMusicHome => 'Создаём ваш музыкальный дом';

  @override
  String get builtIn => 'Встроенный';

  @override
  String by(Object arg1, Object arg2) {
    return '«$arg1» — $arg2';
  }

  @override
  String get bypassAllDspEqDynamicsCrossfade =>
      'Обход всей обработки DSP (EQ, динамика, кроссфейд, скорость) на внутреннем Hi-Res тракте DAP. Отключите для использования программных эффектов. Отключение Bit-perfect (USB DAC) также отключает этот режим.';

  @override
  String get byteInterleavedLrlrStream => 'Побайтовое чередование: поток LRLR';

  @override
  String get calmFrequencies => 'Спокойные частоты';

  @override
  String get camera => 'Камера';

  @override
  String get cameraAccessIsNeededYouCan =>
      'Необходим доступ к камере. Его можно включить в настройках Android.';

  @override
  String get cancel => 'Отмена';

  @override
  String capMs(Object arg1) {
    return 'лимит $arg1 мс';
  }

  @override
  String get capabilities => 'Возможности';

  @override
  String get capabilitiesNotAvailable => 'Сведения о возможностях недоступны';

  @override
  String get capabilityState => 'Состояние возможностей';

  @override
  String get cast => 'Трансляция';

  @override
  String get casting => 'Трансляция';

  @override
  String get castingTapToManage => 'Идёт трансляция — нажмите для управления';

  @override
  String castingTo(Object deviceName) {
    return 'Трансляция на $deviceName';
  }

  @override
  String castingTo2(Object arg1) {
    return 'Трансляция на $arg1';
  }

  @override
  String get categories => 'Категории';

  @override
  String get ceiling => 'Потолок';

  @override
  String get center => 'По центру';

  @override
  String get centeredWidensToFitYourControls =>
      'По центру; расширяется под ваши элементы управления';

  @override
  String ch(Object channels) {
    return '$channels кан.';
  }

  @override
  String ch2(Object ch) {
    return '$ch кан.';
  }

  @override
  String ch3(Object arg1, Object arg2) {
    return '$arg1 / $arg2 кан.';
  }

  @override
  String get changingSampleRateBitDepthOr =>
      'Изменение частоты дискретизации, разрядности или конфигурации каналов может привести к ресемплингу и повлиять на качество звука, высоту тона, скорость или стабильность на некоторых устройствах.';

  @override
  String get channels => 'Каналы';

  @override
  String channels2(Object arg1) {
    return 'Каналов: $arg1';
  }

  @override
  String channels3(Object ch) {
    return 'Каналов: $ch';
  }

  @override
  String get checkTheVersionsYouWantTo =>
      'Отметьте версии, которые нужно оставить — неотмеченные будут удалены из медиатеки. Должна остаться хотя бы одна.';

  @override
  String get checkVersionsToKeepUncheckedWill =>
      'Отметьте нужные версии — остальные будут удалены';

  @override
  String get chooseAction => 'Выберите действие';

  @override
  String get chooseAudioEngine => 'Выбор аудиодвижка';

  @override
  String get chooseLocationU2026 => 'Выбрать расположение…';

  @override
  String get chooseWhichToKeep => 'Выберите, что оставить';

  @override
  String get chromecast => 'Chromecast';

  @override
  String get circularDotsRadiusFollowsAmplitude =>
      'Точки по кругу — радиус следует за амплитудой';

  @override
  String get cityBeats => 'Ритмы города';

  @override
  String get claimedByFlick => 'Захвачено Lokal';

  @override
  String get cleanStraightLineWithPrecisionScrubbing =>
      'Чистая прямая линия с точной перемоткой.';

  @override
  String get clear => 'Очистить';

  @override
  String get clearAll => 'Очистить всё';

  @override
  String get clearAllUac2Settings => 'Сбросить все настройки UAC2';

  @override
  String get clearFilters => 'Сбросить фильтры';

  @override
  String get clearHistory => 'Очистить историю';

  @override
  String get clearLogs => 'Очистить журналы?';

  @override
  String get clearWord => 'Очистить слово';

  @override
  String get clearWords => 'Очистить слова';

  @override
  String get close => 'Закрыть';

  @override
  String get closePreview => 'Закрыть предпросмотр';

  @override
  String codecApplied(Object arg1) {
    return 'Кодек применён: $arg1';
  }

  @override
  String get codecControl => 'Управление кодеком';

  @override
  String get codecForcingUnavailableOnThisDevice =>
      'Принудительный выбор кодека недоступен на этом устройстве — задайте его в разделе «Для разработчиков» → «Аудиокодек Bluetooth».';

  @override
  String get codecInfo => 'О кодеке';

  @override
  String get codecU0026Audio => 'Кодек и аудио';

  @override
  String get collapsed => 'Свёрнуто';

  @override
  String get collection => 'Коллекция';

  @override
  String get color => 'Цвет';

  @override
  String get comingSoon => 'Скоро';

  @override
  String get compatibility => 'Совместимость';

  @override
  String get compatibleWithPowerampEq => 'Совместимо с Poweramp EQ';

  @override
  String get compressor => 'Компрессор';

  @override
  String get compressorOff => 'Компрессор выкл.';

  @override
  String get compressorOn => 'Компрессор вкл.';

  @override
  String get connect => 'Подключить';

  @override
  String get connectAMusicServer => 'Подключить музыкальный сервер';

  @override
  String get connectASubsonicJellyfinWebdavUpnp =>
      'Подключите сервер Subsonic, Jellyfin, WebDAV, UPnP или Tidal для стриминга удалённой медиатеки.';

  @override
  String get connectAUsbDacOrAudio => 'Подключите USB DAC или аудиоинтерфейс';

  @override
  String get connectListenbrainz => 'Подключить ListenBrainz';

  @override
  String get connectToScrobbleYourListeningHistory =>
      'Подключите, чтобы скробблить историю прослушиваний';

  @override
  String get connectToScrobbleYourMusic =>
      'Подключите, чтобы скробблить музыку';

  @override
  String get connectToSubmitYourListeningHistory =>
      'Подключите, чтобы отправлять историю прослушиваний';

  @override
  String get connected => 'Подключено';

  @override
  String get connectedAccount => 'Подключённый аккаунт';

  @override
  String connectedAs(Object username) {
    return 'Подключено как $username';
  }

  @override
  String get connecting => 'Подключение';

  @override
  String get connection => 'Подключение';

  @override
  String get connectionBehavior => 'Поведение при подключении';

  @override
  String get connectionFailedRetry => 'Ошибка подключения — повторить';

  @override
  String get connectionManagement => 'Управление подключением';

  @override
  String get connectionOk => 'Соединение установлено';

  @override
  String get connectionStatus => 'Статус подключения';

  @override
  String containsValuesOutsideTheSupportedRanges(Object presetName) {
    return 'Пресет «$presetName» содержит значения вне поддерживаемого диапазона; они были скорректированы:';
  }

  @override
  String get content => 'Содержимое';

  @override
  String get contentControls => 'Содержимое и управление';

  @override
  String get contentPlacement => 'Расположение содержимого';

  @override
  String get contentPlacement2 => 'Расположение содержимого';

  @override
  String get continueLabel => 'Продолжить';

  @override
  String conversionFailed(Object error) {
    return 'Ошибка конвертации: $error';
  }

  @override
  String convertedSuccessfully(Object fileName) {
    return 'Файл $fileName успешно конвертирован';
  }

  @override
  String get convertingAudio => 'Конвертация аудио...';

  @override
  String convertingToWav(Object fileName) {
    return 'Конвертация $fileName в WAV...';
  }

  @override
  String get convolverImpulseResponse =>
      'Конвольвер / импульсная характеристика';

  @override
  String copies(Object arg1, Object arg2) {
    return '$arg1 • копий: $arg2';
  }

  @override
  String get copy => 'Копировать';

  @override
  String get copyLink => 'Копировать ссылку';

  @override
  String get copyYourUserTokenFromListenbrainz =>
      'Скопируйте пользовательский токен в настройках ListenBrainz и вставьте его ниже.';

  @override
  String get copyright => 'Авторские права';

  @override
  String get cornerRadius => 'Скругление углов';

  @override
  String get cosmicOrchestra => 'Космический оркестр';

  @override
  String get couldNotConnectToLastFm =>
      'Не удалось подключиться к Last.fm. Проверьте учётные данные API и попробуйте снова.';

  @override
  String get couldNotConnectToListenbrainzCheck =>
      'Не удалось подключиться к ListenBrainz. Проверьте токен и попробуйте снова.';

  @override
  String get couldNotLoadAlbumSongs => 'Не удалось загрузить треки альбома';

  @override
  String get couldNotCreateThePosterImage =>
      'Не удалось создать изображение постера.';

  @override
  String get couldNotLoadArtistSongs =>
      'Не удалось загрузить треки исполнителя';

  @override
  String couldNotLoadIr(Object e) {
    return 'Не удалось загрузить IR: $e';
  }

  @override
  String get couldNotLoadSession => 'Не удалось загрузить сессию';

  @override
  String get couldNotOpenBrowser => 'Не удалось открыть браузер.';

  @override
  String get couldNotOpenKoFiPlease =>
      'Не удалось открыть Ko-fi. Пожалуйста, попробуйте снова.';

  @override
  String couldNotOpenLink2(Object e) {
    return 'Не удалось открыть ссылку: $e';
  }

  @override
  String get couldNotOpenThatPhotoTry =>
      'Не удалось открыть это фото. Попробуйте другое изображение.';

  @override
  String get couldNotOpenThePlayStore => 'Не удалось открыть Play Store.';

  @override
  String couldNotOpenThePlayStore2(Object error) {
    return 'Не удалось открыть Play Store: $error';
  }

  @override
  String get couldNotReadTheCoverColors =>
      'Не удалось считать цвета обложки. Стиль «Сигнал» по-прежнему доступен.';

  @override
  String get couldNotReadTheSelectedLyrics =>
      'Не удалось прочитать выбранный файл текста песни.';

  @override
  String get couldNotSaveTheLyricsFile =>
      'Не удалось сохранить файл текста песни.';

  @override
  String get couldNotSaveYourRecapPlease =>
      'Не удалось сохранить итоги. Пожалуйста, попробуйте снова.';

  @override
  String get couldNotUseTheSelectedLyrics =>
      'Не удалось использовать выбранный файл текста песни.';

  @override
  String get couldnTOpenTheBrowserAutomatically =>
      'Не удалось автоматически открыть браузер. Авторизуйтесь на любом устройстве по этой ссылке — вход завершится автоматически:';

  @override
  String get countingFiles => 'Подсчёт файлов…';

  @override
  String get create => 'Создать';

  @override
  String get createACollection => 'Создать коллекцию';

  @override
  String get createACustomPreset => 'Создать собственный пресет';

  @override
  String get createAPlaylistImportAnM3u =>
      'Создайте плейлист, импортируйте M3U или позвольте миксам выше задать настроение.';

  @override
  String get createLyrics => 'Создать текст';

  @override
  String get createNewPlaylist => 'Создать новый плейлист';

  @override
  String get createNewPlaylist2 => 'Создать новый плейлист';

  @override
  String get createPlaylist => 'Создать плейлист';

  @override
  String get createPlaylistFromSelected => 'Создать плейлист из выбранных';

  @override
  String get createYourFirstPlaylistOrJump =>
      'Создайте свой первый плейлист или откройте сохранённые коллекции.';

  @override
  String get createYourFirstPlaylistToOrganize =>
      'Создайте свой первый плейлист, чтобы\nупорядочить любимые треки';

  @override
  String created(Object arg1) {
    return 'Создано: $arg1';
  }

  @override
  String createdAndAddedSong(Object arg1) {
    return 'Создан «$arg1» и добавлен трек';
  }

  @override
  String createdAndAddedSongs(Object name, Object arg1) {
    return 'Создан «$name», добавлено треков: $arg1';
  }

  @override
  String get creativeFx => 'Творческие эффекты';

  @override
  String credentialsRejectedByReEnterThe(Object arg1) {
    return 'Сервер $arg1 отклонил учётные данные. Введите пароль заново.';
  }

  @override
  String get credentialsSavedSuccessfully =>
      'Учётные данные успешно сохранены!';

  @override
  String get crystalCaverns => 'Хрустальные пещеры';

  @override
  String get cueSheetTracksCannotBeEdited =>
      'Треки из CUE-разметки нельзя редактировать.';

  @override
  String get cueSheetTracksCannotBeEdited2 =>
      'Треки из CUE-разметки нельзя редактировать';

  @override
  String get currentArtwork => 'Текущая обложка';

  @override
  String get currentCustomArt => 'Текущая пользовательская обложка';

  @override
  String get currentPlaybackMode => 'Текущий режим воспроизведения';

  @override
  String currentRoute(Object arg1) {
    return 'Текущий маршрут: $arg1.';
  }

  @override
  String get currentSongPreviewOnly => 'Текущий трек · только предпросмотр';

  @override
  String get currentStreak => 'Текущая серия';

  @override
  String get curvePreview => 'Предпросмотр кривой';

  @override
  String get curvedWave => 'Изогнутая волна';

  @override
  String get custom => 'Пользовательский';

  @override
  String get customFormat => 'Пользовательский формат';

  @override
  String get customFormatForcesPlaybackToThe =>
      'Пользовательский формат принудительно задаёт выбранный формат вывода. Если частота дискретизации, разрядность или каналы не подходят для трека или устройства, звук может искажаться, меняться по высоте или скорости либо работать нестабильно.';

  @override
  String get customFormatIsDisabledInBit =>
      'Пользовательский формат отключён в режиме Bit-perfect (USB DAC), так как требуется точное соответствие частоты дискретизации. Отключите Bit-perfect (USB DAC), чтобы задать собственный формат.';

  @override
  String get customFormatIsUnavailableBecauseAudio =>
      'Пользовательский формат недоступен, так как параметр «Формат аудио» отключён в настройках.';

  @override
  String get customWidth => 'Своя ширина';

  @override
  String get customizeAudioDisplayNavigationAnd =>
      'Настройте звук, интерфейс, навигацию и интеграции.';

  @override
  String get customizeBottomBar => 'Настройка нижней панели';

  @override
  String dAgo(Object arg1) {
    return '$arg1 дн. назад';
  }

  @override
  String dAgo2(Object arg1) {
    return '$arg1 дн. назад';
  }

  @override
  String get dacClaim => 'Захват ЦАП';

  @override
  String dacWillBeOfferedAgain(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count ЦАП будут предложены снова.',
      many: '$count ЦАП будут предложены снова.',
      few: '$count ЦАП будут предложены снова.',
      one: '$count ЦАП будет предложен снова.',
    );
    return '$_temp0';
  }

  @override
  String get daily => 'Ежедневно';

  @override
  String get damp => 'Демпфирование';

  @override
  String get dapNativeBitOrder => 'Нативный порядок бит DAP';

  @override
  String get dapNativeByteGrouping => 'Нативная группировка байт DAP';

  @override
  String get dark => 'Тёмная';

  @override
  String get date => 'Дата';

  @override
  String get dateAdded => 'Дата добавления';

  @override
  String get dateAddedNewest => 'Дата добавления (сначала новые)';

  @override
  String get dateAddedOldest => 'Дата добавления (сначала старые)';

  @override
  String get dayStreak => 'дней подряд';

  @override
  String get dayStreak2 => 'Серия дней';

  @override
  String get dayStreak3 => 'Серия дней';

  @override
  String dayUnit(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'дней',
      many: 'дней',
      few: 'дня',
      one: 'день',
    );
    return '$_temp0';
  }

  @override
  String db10(Object arg1) {
    return '$arg1 дБ';
  }

  @override
  String db13(Object arg1) {
    return '$arg1 дБ';
  }

  @override
  String db15(Object arg1, Object arg2) {
    return '$arg1%  $arg2 дБ';
  }

  @override
  String db2(Object value) {
    return '$value дБ';
  }

  @override
  String db9(Object arg1) {
    return '$arg1 дБ';
  }

  @override
  String dbCut(Object arg1) {
    return 'срез $arg1 дБ';
  }

  @override
  String dbMax(Object arg1) {
    return 'макс. $arg1 дБ';
  }

  @override
  String get deactivateFallback => 'Отключить резервный режим';

  @override
  String get dec => 'Дек';

  @override
  String get decode => 'Декодирование';

  @override
  String get deepEarth => 'Глубины земли';

  @override
  String get defaultAndroidPlaybackEngineUsedBy =>
      'Стандартный движок воспроизведения Android, используемый Lokal сейчас.';

  @override
  String get defaultAndroidPlayerPlaysEverything =>
      'Стандартный плеер Android — надёжно воспроизводит всё. Самый безопасный выбор для большинства слушателей.';

  @override
  String get delays => 'Задержки';

  @override
  String get delete => 'Удалить';

  @override
  String deleteAndAllSongsAndPlaylists(Object arg1) {
    return 'Удалить «$arg1», а также все синхронизированные с ним треки и плейлисты? Кэшированные загрузки сохранятся.';
  }

  @override
  String get deleteFile => 'Удалить файл';

  @override
  String get deleteFiles => 'Удалить файлы';

  @override
  String get deletePlaylist => 'Удалить плейлист';

  @override
  String get deletePreset => 'Удалить пресет?';

  @override
  String get deleteSelected => 'Удалить выбранное';

  @override
  String get deleteSong => 'Удалить трек';

  @override
  String get deleteSong2 => 'Удалить трек?';

  @override
  String get deleteSong3 => 'Удалить трек';

  @override
  String deleteSongs(Object arg1) {
    return 'Удалить выбранные треки ($arg1)?';
  }

  @override
  String get deleteSongs2 => 'Удалить треки';

  @override
  String deleteThisCannotBeUndone(Object arg1) {
    return 'Удалить «$arg1»? Это действие нельзя отменить.';
  }

  @override
  String deleted(Object arg1) {
    return 'Удалено: «$arg1»';
  }

  @override
  String deletedSongs(Object arg1) {
    return 'Удалено треков: $arg1';
  }

  @override
  String get deselectAll => 'Снять выделение';

  @override
  String get designed => 'Дизайнерский';

  @override
  String get details => 'Подробности';

  @override
  String get developerMode => 'Режим разработчика';

  @override
  String get developerOptionsIsDisabledEnableIt =>
      'Параметры разработчика отключены. Включите их в разделе «Настройки» → «О телефоне» (нажмите 7 раз на «Номер сборки»), затем повторите попытку.';

  @override
  String get device => 'Устройство';

  @override
  String get deviceCapabilities => 'Возможности устройства';

  @override
  String get deviceConnected => 'Устройство подключено';

  @override
  String get deviceDac => 'ЦАП устройства';

  @override
  String get deviceDacVolume => 'Громкость ЦАП устройства';

  @override
  String get deviceDisconnected => 'Устройство отключено';

  @override
  String get deviceInformation => 'Сведения об устройстве';

  @override
  String get deviceType => 'Тип устройства';

  @override
  String get devices => 'Устройства';

  @override
  String get direct => 'Прямой';

  @override
  String get directAlsaOutputIsActiveAnd =>
      'Активен прямой вывод ALSA в обход аудиосервера Android.';

  @override
  String get directLibusbIsochronousUsbEngineBest =>
      'Прямой изохронный USB-движок на базе libusb. Лучше всего работает с Bit-perfect (USB DAC) для подтверждённого вывода на внешний ЦАП.';

  @override
  String get directUsb => 'Прямой USB';

  @override
  String get directUsbDeviceManaged => 'Прямой USB (управляется устройством)';

  @override
  String get directUsbExperimental => 'Прямой USB (экспериментальный)';

  @override
  String get disabled => 'Отключено';

  @override
  String get disabledInBitPerfectUsbDac =>
      'Отключено в режиме Bit-perfect (USB DAC) (требуется точная частота)';

  @override
  String get disabledWhileBothBitPerfectOptions =>
      'Отключено, пока оба параметра Bit-perfect выключены на этом DAP.';

  @override
  String get disc => 'Диск';

  @override
  String get disc2 => 'Диск №';

  @override
  String get discard => 'Отменить';

  @override
  String get discardChanges => 'Отменить изменения?';

  @override
  String get discardChanges2 => 'Отменить изменения?';

  @override
  String get disconnect => 'Отключить';

  @override
  String disconnectFrom(Object arg1) {
    return 'Отключиться от $arg1';
  }

  @override
  String get disconnectLastFm => 'Отключить Last.fm?';

  @override
  String get disconnectListenbrainz => 'Отключить ListenBrainz?';

  @override
  String get discoversDlnaUpnpAndChromecastReceivers =>
      'Ищет приёмники DLNA, UPnP и Chromecast в вашей сети';

  @override
  String get dismiss => 'Закрыть';

  @override
  String get displayFileFormatAndBitrateIn =>
      'Показывать формат файла и битрейт в иммерсивном режиме';

  @override
  String get displayFileFormatAndBitrateIn2 =>
      'Показывать формат файла и битрейт в режиме карточки обложки';

  @override
  String get displayTheAlbumNameInArtwork =>
      'Показывать название альбома в режиме карточки обложки';

  @override
  String get displayTheArtistNameInArtwork =>
      'Показывать имя исполнителя в режиме карточки обложки';

  @override
  String get displayTheArtistNameInImmersive =>
      'Показывать имя исполнителя в иммерсивном режиме';

  @override
  String get displayTheTrackTitleInArtwork =>
      'Показывать название трека в режиме карточки обложки';

  @override
  String get displayTheTrackTitleInImmersive =>
      'Показывать название трека в иммерсивном режиме';

  @override
  String get dlnaAndUpnpReceiversAreControlled =>
      'Управление приёмниками DLNA и UPnP реализовано напрямую на чистом Dart — без лишних зависимостей. Поддержка Chromecast использует нативный Cast SDK. Транслировать можно сетевые источники (Subsonic, WebDAV, Jellyfin, UPnP), локальные файлы и кэшированные треки — локальные файлы передаются напрямую с этого телефона. Во время трансляции кнопки громкости и системная панель громкости управляют подключённым устройством.';

  @override
  String get dlnaUpnp => 'DLNA / UPnP';

  @override
  String get donTShowAgainToday => 'Больше не показывать сегодня';

  @override
  String get done => 'Готово';

  @override
  String get dop => 'DoP';

  @override
  String get dots => 'Точки';

  @override
  String get doubleTapABandToReset => 'Дважды нажмите на полосу для сброса';

  @override
  String get doubleTapToReset => 'Дважды нажмите для сброса';

  @override
  String get doubleTapToResetThisBand =>
      'Дважды нажмите, чтобы сбросить эту полосу';

  @override
  String down(Object arg1) {
    return '$arg1 вниз';
  }

  @override
  String dp(Object arg1) {
    return '$arg1 dp';
  }

  @override
  String dp2(Object arg1) {
    return '$arg1 dp';
  }

  @override
  String dp3(Object arg1) {
    return '$arg1 dp';
  }

  @override
  String get dragABoundaryToStretchOr =>
      'Перетащите границу, чтобы растянуть или сжать слово перед ней. Последняя граница сдвигает следующую строку.';

  @override
  String get dragBandsUpOrDown => 'Перетаскивайте полосы вверх или вниз';

  @override
  String get dragToChangeFrequencyGain =>
      'Перетащите для изменения частоты и усиления';

  @override
  String get dragToMovePinchToWiden =>
      'Перетащите для сдвига • Сведите/разведите для ширины';

  @override
  String get dragVerticallyToChangeGain =>
      'Перетащите по вертикали для изменения усиления';

  @override
  String driftMs(Object arg1) {
    return 'Дрейф $arg1 мс';
  }

  @override
  String get dsdMode => 'Режим DSD';

  @override
  String get dsdOutputMode => 'Режим вывода DSD';

  @override
  String get dsdStream => 'Поток DSD';

  @override
  String get duplicateCleaner => 'Очистка дубликатов';

  @override
  String get duplicatesRemovedUsingRecommendedPicks =>
      'Дубликаты удалены с использованием рекомендуемых вариантов.';

  @override
  String get duration => 'Длительность';

  @override
  String get durationMatch => 'Совпадение по длительности';

  @override
  String get dynamics => 'Динамика';

  @override
  String get earlier => 'Ранее';

  @override
  String get earlierStandoutsPulledBackIntoView =>
      'Яркие треки из вашей истории прослушивания, к которым стоит вернуться.';

  @override
  String get editCredentials => 'Изменить учётные данные';

  @override
  String get editDescription => 'Изменить описание';

  @override
  String get editDescription2 => 'Изменить описание';

  @override
  String get editMetadata => 'Редактировать метаданные';

  @override
  String get editServer => 'Изменить сервер';

  @override
  String get editSync => 'Редактировать и синхронизировать';

  @override
  String get editText => 'Редактировать текст';

  @override
  String get editToken => 'Изменить токен';

  @override
  String get empty => 'Пусто';

  @override
  String get emptyLine => '(Пустая строка)';

  @override
  String get enable => 'Включить';

  @override
  String get enable432HzTuning => 'Включить строй 432 Гц?';

  @override
  String get enableEqToEdit => 'Включите EQ для редактирования';

  @override
  String get enabled => 'Включено';

  @override
  String get endpoint => 'Конечная точка';

  @override
  String get engine => 'Движок';

  @override
  String enterAValidNumber(Object label) {
    return 'Введите корректное значение поля «$label»';
  }

  @override
  String enterAValueFromTo(Object arg1, Object arg2) {
    return 'Введите значение от $arg1% до $arg2%';
  }

  @override
  String get enterAYear19999 => 'Введите год (1–9999)';

  @override
  String get enterYourApiKey => 'Введите ваш API-ключ';

  @override
  String get enterYourSharedSecret => 'Введите ваш общий секрет';

  @override
  String ep(Object arg1) {
    return 'EP $arg1';
  }

  @override
  String get equalizer => 'Эквалайзер';

  @override
  String error(Object error) {
    return 'Ошибка: $error';
  }

  @override
  String error2(Object arg1) {
    return 'Ошибка: $arg1';
  }

  @override
  String get error3 => 'Ошибка';

  @override
  String errorLoadingCapabilities(Object error) {
    return 'Ошибка загрузки возможностей: $error';
  }

  @override
  String get errorLoadingPlaylists => 'Ошибка загрузки плейлистов';

  @override
  String errorLoadingPlaylists2(Object error) {
    return 'Ошибка загрузки плейлистов: $error';
  }

  @override
  String get errorLoadingPreference => 'Ошибка загрузки настройки';

  @override
  String get errorLoadingSongs => 'Ошибка загрузки треков';

  @override
  String get etherealTones => 'Эфирные тона';

  @override
  String get everyAlbumHasArtistAndAlbum =>
      'У всех альбомов заполнены теги исполнителя и альбома.';

  @override
  String get exactMatch => 'Точное совпадение';

  @override
  String get exclusiveDirectPcmIsActiveAnd =>
      'Активен эксклюзивный прямой вывод PCM в обход микшера Android с исходной частотой трека.';

  @override
  String get exclusiveUsbBitPerfectReEngaged =>
      'Эксклюзивный USB Bit-perfect снова активен.';

  @override
  String get exclusiveUsbDroppedToTheAndroid =>
      'Эксклюзивный USB переключился на микшер Android. Bit-perfect приостановлен.';

  @override
  String get exclusiveUsbIsActiveAndBypassing =>
      'Эксклюзивный USB активен и работает в обход микшера Android.';

  @override
  String get exclusiveUsbIsStillUnavailableCheck =>
      'Эксклюзивный USB по-прежнему недоступен. Проверьте диагностику USB.';

  @override
  String get expanded => 'Развёрнутый';

  @override
  String get experimental => 'Экспериментально';

  @override
  String get experimentalDownTunePlaybackBy432 =>
      'Экспериментально — понижение строя воспроизведения на 432/440. Отключает прямую передачу Bit-perfect и задействует DSP-тракт.';

  @override
  String get exportAsM3u => 'Экспорт в .m3u';

  @override
  String get exportAsM3u8 => 'Экспорт в .m3u8';

  @override
  String get exportCsv => 'Экспорт CSV';

  @override
  String get exportCurrentPreset => 'Экспортировать текущий пресет';

  @override
  String get exportEqualizerPreset => 'Экспорт пресета эквалайзера';

  @override
  String exportFailed(Object e) {
    return 'Ошибка экспорта: $e';
  }

  @override
  String get exportFormat => 'Формат экспорта';

  @override
  String get exportTxt => 'Экспорт TXT';

  @override
  String exportedPresetTo(Object savePath) {
    return 'Пресет экспортирован в $savePath';
  }

  @override
  String exportedPresetTo2(Object fallbackPath) {
    return 'Пресет экспортирован в $fallbackPath';
  }

  @override
  String exportedSongsTo(Object arg1, Object arg2) {
    return 'Экспортировано треков ($arg1) в «$arg2».';
  }

  @override
  String get externalLabel => 'Внешний';

  @override
  String get externalSongsCannotBeEdited =>
      'Внешние треки нельзя редактировать.';

  @override
  String get externalSongsCannotBeEdited2 =>
      'Внешние треки нельзя редактировать';

  @override
  String get extraCovers => 'Дополнительные обложки';

  @override
  String get failedToActivateFallback =>
      'Не удалось активировать резервный вывод';

  @override
  String failedToAddToFavorites(Object arg1) {
    return 'Не удалось добавить «$arg1» в избранное';
  }

  @override
  String get failedToDeactivateFallback =>
      'Не удалось отключить резервный вывод';

  @override
  String get failedToImportPresetFile =>
      'Не удалось импортировать файл пресета.';

  @override
  String failedToSaveMetadata(Object e) {
    return 'Не удалось сохранить метаданные: $e';
  }

  @override
  String get failedToSaveMetadata2 => 'Не удалось сохранить метаданные.';

  @override
  String get failedToStartStreaming =>
      'Не удалось запустить потоковое воспроизведение';

  @override
  String get failedToStopStreaming =>
      'Не удалось остановить потоковое воспроизведение';

  @override
  String get faintHueShiftFromAlbumArt =>
      'Лёгкий цветовой оттенок от обложки альбома.';

  @override
  String get fallback => 'Резервный режим';

  @override
  String get fallbackAudio => 'Резервный аудиовыход';

  @override
  String get fallbackAudioActivated => 'Резервный аудиовыход активирован';

  @override
  String get fallbackAudioDeactivated => 'Резервный аудиовыход отключён';

  @override
  String get fallbackAudioWillBeUsedIf =>
      'При сбое устройства UAC2 будет использоваться резервный аудиовыход';

  @override
  String get fastDirectTrackingImmediateResponse =>
      'Быстрое прямое отслеживание — мгновенный отклик';

  @override
  String get favoriteAll => 'Добавить все в избранное';

  @override
  String get favoriteSongs => 'Избранные треки';

  @override
  String get favorites => 'Избранное';

  @override
  String get favoritesYouHaveNotRevisitedLately =>
      'Избранное, к которому вы давно не возвращались';

  @override
  String get feb => 'Фев';

  @override
  String get feedback => 'Обратная связь';

  @override
  String get file => 'Файл';

  @override
  String get fileInformation => 'Сведения о файле';

  @override
  String get filePath => 'Путь к файлу';

  @override
  String files2(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count файлов',
      many: '$count файлов',
      few: '$count файла',
      one: '$count файл',
    );
    return '$_temp0';
  }

  @override
  String get filter => 'Фильтр';

  @override
  String get filterByFormat => 'ФИЛЬТР ПО ФОРМАТУ';

  @override
  String get filterLogs => 'Фильтр журналов…';

  @override
  String get findAndCleanUpDuplicateSongs =>
      'Поиск и удаление дубликатов треков';

  @override
  String get findSongsArtistsAlbumsFolders =>
      'Поиск треков, исполнителей, альбомов, папок…';

  @override
  String finishingMetadataForSongs(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Завершение обработки метаданных для $count треков…',
      many: 'Завершение обработки метаданных для $count треков…',
      few: 'Завершение обработки метаданных для $count треков…',
      one: 'Завершение обработки метаданных для $count трека…',
    );
    return '$_temp0';
  }

  @override
  String get finishingUp => 'Завершение…';

  @override
  String get fix => 'Исправить';

  @override
  String get fixMissingMetadata => 'Исправить недостающие метаданные';

  @override
  String get fixedBands => '31 фиксированная полоса';

  @override
  String fixedCenterFrequenciesWithADb(Object arg1) {
    return 'Фиксированные центральные частоты с диапазоном $arg1 дБ. Нажмите для настройки.';
  }

  @override
  String get flac24Bit96Khz => 'FLAC · 24 бит / 96 кГц';

  @override
  String get flat => 'Ровный';

  @override
  String get flatResponse => 'Ровная АЧХ';

  @override
  String get flickCanAttemptToPreferA =>
      'Lokal может попытаться выбрать указанный выше кодек, но результат зависит от вашего устройства, наушников и версии Android. Принудительный выбор кодека использует скрытый системный API и может не работать без root-прав.';

  @override
  String get flickPreview => 'Предпросмотр Lokal';

  @override
  String get flickReplay => 'Lokal Replay';

  @override
  String get flickWillForceYourChosenCodec =>
      'Lokal будет принудительно включать выбранный кодек при подключении';

  @override
  String get folder => 'Папка';

  @override
  String get folderLimit => 'ЛИМИТ ПАПОК';

  @override
  String get folderName => 'Имя папки';

  @override
  String folderOf2(Object current, Object total) {
    return 'Папка $current из $total';
  }

  @override
  String get folderSongCount => 'Количество треков в папке';

  @override
  String get folders => 'Папки';

  @override
  String get foldersShownPerPage => 'Папок на странице';

  @override
  String get fontScale => 'Масштаб шрифта';

  @override
  String get footerLine => 'Нижняя строка';

  @override
  String get forceDop => 'Принудительно DoP';

  @override
  String get forceDopAlwaysUseDsdOver =>
      'Принудительно DoP — всегда использовать DSD over PCM (USB DAC)';

  @override
  String get forcePcm => 'Принудительно PCM';

  @override
  String get forcePcmAlwaysConvertDsdTo =>
      'Принудительно PCM — всегда конвертировать DSD в PCM';

  @override
  String get format => 'Формат';

  @override
  String get formatControlsAreDisabledTheEngine =>
      'Управление форматом отключено. Движок использует формат по умолчанию.';

  @override
  String get formatStrategy => 'Стратегия формата';

  @override
  String get formatStrategyAndCustomFormatControls =>
      'Стратегия формата и ручные настройки формата активны.';

  @override
  String get formatStrategyIsDisabledInBit =>
      'Стратегия формата отключена в режиме Bit-perfect (USB DAC), так как требуется точное совпадение частоты дискретизации. Отключите Bit-perfect (USB DAC), чтобы изменить настройки формата.';

  @override
  String get formatStrategyIsUnavailableBecauseAudio =>
      'Стратегия формата недоступна, так как параметр «Аудиоформат» отключён в настройках.';

  @override
  String foundOnline(Object arg1) {
    return 'Найдено в сети: «$arg1».';
  }

  @override
  String frPkt(Object arg1) {
    return '$arg1 кадр./пак.';
  }

  @override
  String get freq => 'Част.';

  @override
  String get frequency => 'Частота';

  @override
  String get frequencyFocus => 'Частотный фокус';

  @override
  String get freshAdditions => 'Свежие добавления';

  @override
  String from(Object sourceLabel) {
    return 'Из $sourceLabel';
  }

  @override
  String get fromSquareCornersToARounded =>
      'От прямых углов к скруглённой панели';

  @override
  String get fullBleedAlbumArtWithThe =>
      'Полноэкранная обложка альбома в текущем кинематографическом стиле.';

  @override
  String get fullPlayer => 'Полный плеер';

  @override
  String get fullSpectrum => 'Полный спектр';

  @override
  String get fullViewCardSize => 'Размер карточки в полном режиме';

  @override
  String get fullViewCardSize2 => 'Размер карточки в полном режиме';

  @override
  String get fullscreen => 'На весь экран';

  @override
  String get fxOff => 'Эффекты выкл.';

  @override
  String get fxOn => 'Эффекты вкл.';

  @override
  String get gain => 'Усиление';

  @override
  String get gallery => 'Галерея';

  @override
  String get gapAboveNavigation => 'Отступ над навигацией';

  @override
  String gb(Object arg1) {
    return '$arg1 ГБ';
  }

  @override
  String get generatedFromYourListeningHabitsFavorites =>
      'Собрано на основе ваших привычек прослушивания, избранного и недавних добавлений.';

  @override
  String get genre => 'Жанр';

  @override
  String get getStarted => 'Начать';

  @override
  String get getYourApiCredentials => 'Получить учётные данные API';

  @override
  String get goToAlbum => 'Перейти к альбому';

  @override
  String get goToArtist => 'Перейти к исполнителю';

  @override
  String get goodAfternoon => 'Добрый день';

  @override
  String get goodEvening => 'Добрый вечер';

  @override
  String get goodMorning => 'Доброе утро';

  @override
  String get gotIt => 'Понятно';

  @override
  String get grantBluetoothAccess => 'Предоставить доступ к Bluetooth';

  @override
  String get graphic => 'Графический';

  @override
  String get graphicEq => 'Графический EQ';

  @override
  String get green => 'Зелёный';

  @override
  String get groupingByTitleArtistThisIs =>
      'Группировка по названию и исполнителю — обычно это быстро.';

  @override
  String get groups => 'Группы';

  @override
  String groupsToRemove(Object arg1, Object arg2) {
    return 'Групп: $arg1 • К удалению: $arg2';
  }

  @override
  String groupsToRemove2(Object arg1, Object toRemove) {
    return 'Групп: $arg1 • К удалению: $toRemove';
  }

  @override
  String get growsFurtherIfLargerSystemText =>
      'Дополнительно увеличивается, если системному шрифту нужно больше места';

  @override
  String hAgo(Object arg1) {
    return '$arg1 ч назад';
  }

  @override
  String get hardwareUsbDac => 'Аппаратная (USB DAC)';

  @override
  String get hardwareVolumeIsDetectedButWrites =>
      'Аппаратная регулировка громкости обнаружена, но изменение заблокировано во время активного прямого USB-воспроизведения.';

  @override
  String get hasArtwork => 'Есть обложка';

  @override
  String get heavyRotation => 'На повторе';

  @override
  String get held => 'Удерживается';

  @override
  String get hiResDirect => 'Hi-Res Direct';

  @override
  String get hideLyrics => 'Скрыть текст песни';

  @override
  String get hidePassword => 'Скрыть пароль';

  @override
  String get hideVisualizer => 'Скрыть визуализатор';

  @override
  String get hideVisualizer2 => 'Скрыть визуализатор';

  @override
  String get highFrequenciesOnly => 'Только высокие частоты';

  @override
  String get highPass => 'Фильтр ВЧ';

  @override
  String get highQuality => 'Высокое качество';

  @override
  String get highQualityEngine => 'Движок высокого качества';

  @override
  String get highQualityWidelySupported =>
      'Высокое качество, широкая поддержка';

  @override
  String get highResolutionAptx => 'aptX высокого разрешения';

  @override
  String get highShelf => 'Полка ВЧ';

  @override
  String get highestBitrateUpTo990Kbps =>
      'Максимальный битрейт (до 990 кбит/с)';

  @override
  String get highestQuality => 'Наивысшее качество';

  @override
  String get historyCleared => 'История очищена';

  @override
  String hourUnit(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'часов',
      many: 'часов',
      few: 'часа',
      one: 'час',
    );
    return '$_temp0';
  }

  @override
  String get httpBasicNeedsItRecoverableStored =>
      'Для HTTP Basic пароль должен быть восстановимым; хранится в закодированном виде';

  @override
  String hz(Object rate) {
    return '$rate Гц';
  }

  @override
  String hz3(Object hz) {
    return '$hz Гц';
  }

  @override
  String get hz5 => 'Гц';

  @override
  String hz6(Object arg1) {
    return '$arg1 Гц';
  }

  @override
  String get hzTuning => 'Строй 432 Гц';

  @override
  String identified(int count, Object note) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Распознано $count треков',
      many: 'Распознано $count треков',
      few: 'Распознано $count трека',
      one: 'Распознан $count трек',
    );
    return '$_temp0$note.';
  }

  @override
  String get identifyAlbum => 'Распознать альбом';

  @override
  String get identifyAlbum2 => 'Распознать альбом';

  @override
  String get idle => 'Ожидание';

  @override
  String get immersive => 'Иммерсивный';

  @override
  String importFailed(Object e) {
    return 'Ошибка импорта: $e';
  }

  @override
  String get importM3uM3u8 => 'Импорт M3U/M3U8';

  @override
  String get importPresetFile => 'Импорт файла пресета';

  @override
  String imported(Object arg1) {
    return 'Импортировано: «$arg1»';
  }

  @override
  String get importedArtIsSavedInsideThe =>
      'Импортированная обложка сохраняется внутри приложения и применяется ко всем трекам этого альбома.';

  @override
  String get importedArtIsSavedInsideThe2 =>
      'Импортированная обложка сохраняется внутри приложения только для этого трека.';

  @override
  String importedWithSongs(Object arg1, Object arg2, Object unmatchedText) {
    return 'Импортирован «$arg1» (треков: $arg2).$unmatchedText';
  }

  @override
  String get impulseResponse => 'Импульсная характеристика';

  @override
  String inLabel(Object folder) {
    return 'в $folder';
  }

  @override
  String inYourLibrary(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count треков',
      many: '$count треков',
      few: '$count трека',
      one: '$count трек',
    );
    return '$_temp0 в вашей медиатеке';
  }

  @override
  String get inactive => 'Неактивно';

  @override
  String get incredibleOverAMonthOfDaily =>
      'Невероятно — больше месяца ежедневного прослушивания.';

  @override
  String get inputGain => 'Входное усиление';

  @override
  String get inst => 'Инстр.';

  @override
  String get instructions => 'Инструкции';

  @override
  String get instrumental => 'Инструментал';

  @override
  String get interactiveEq => 'Интерактивный EQ';

  @override
  String get interfaceClaimed => 'Интерфейс захвачен';

  @override
  String get isochronousUsb => 'Изохронный USB';

  @override
  String items(Object count) {
    return 'Элементов: $count';
  }

  @override
  String get jan => 'Янв';

  @override
  String get jellyfin => 'Jellyfin';

  @override
  String get jellyfinEmby => 'Jellyfin · Emby';

  @override
  String get jul => 'Июл';

  @override
  String get jumpBackIn => 'Продолжить прослушивание';

  @override
  String get jun => 'Июн';

  @override
  String get justAudioExoplayer => 'just_audio / ExoPlayer';

  @override
  String get justAudioExoplayerDefault =>
      'just_audio / ExoPlayer (по умолчанию)';

  @override
  String get justNow => 'Только что';

  @override
  String get karaokePreview => 'Предпросмотр караоке';

  @override
  String kb(Object arg1) {
    return '$arg1 КБ';
  }

  @override
  String get keepAll => 'Оставить все';

  @override
  String get keepEditing => 'Продолжить редактирование';

  @override
  String get keepItGoingOpenTomorrowTo =>
      'Так держать. Откройте приложение завтра, чтобы продлить серию.';

  @override
  String get keepListeningWithFlick => 'Продолжайте слушать с Lokal';

  @override
  String get keepPlaybackPausedWhenADevice =>
      'Оставлять воспроизведение на паузе при переподключении устройства';

  @override
  String get keepTheSessionMovingOrHead =>
      'Продолжите сессию или вернитесь прямо к плееру.';

  @override
  String keeping(Object type, Object br) {
    return 'Оставить • $type • $br';
  }

  @override
  String keepingOfToRemove(Object keptCount, Object arg1, Object removeCount) {
    return 'Остаётся $keptCount из $arg1 • К удалению: $removeCount';
  }

  @override
  String get keepingThisVersion => 'Оставить эту версию';

  @override
  String get keepsSoftwareVolumeAndDspActive =>
      'Сохраняет программную громкость и DSP активными в общем тракте DAP.';

  @override
  String get keptInSecureStorageToRe =>
      'Хранится в защищённом хранилище для повторного входа при истечении срока токена';

  @override
  String keptWillBeRemoved(Object keptCount, Object removeCount) {
    return 'Оставлено: $keptCount • Будет удалено: $removeCount';
  }

  @override
  String khz(Object arg1) {
    return '$arg1 кГц';
  }

  @override
  String khz2(Object arg1) {
    return '$arg1 кГц';
  }

  @override
  String khzBit(Object arg1, Object arg2) {
    return '$arg1 кГц/$arg2 бит';
  }

  @override
  String khzBit2(Object arg1, Object arg2) {
    return '$arg1 кГц/$arg2 бит';
  }

  @override
  String khzBitCh(Object arg1, Object arg2, Object arg3) {
    return '$arg1 кГц / $arg2 бит / $arg3 кан.';
  }

  @override
  String get label => 'Лейбл';

  @override
  String get labelOrganization => 'Лейбл / Организация';

  @override
  String get lastFm => 'Last.fm';

  @override
  String get lastFmConfiguration => 'Настройка Last.fm';

  @override
  String get lastFmConnected => 'Last.fm подключён';

  @override
  String get lastFmConnected2 => 'Last.fm подключён!';

  @override
  String get lastPick => 'Последний выбор';

  @override
  String get lastWeek => 'Прошлая неделя';

  @override
  String get lateNightSessions => 'Ночные сессии';

  @override
  String get latestArrivalsFromYourLibrary =>
      'Последние новинки вашей медиатеки';

  @override
  String get layered => 'Слои';

  @override
  String get layoutMode => 'Режим макета';

  @override
  String get ldac330Kbps => 'LDAC 330 кбит/с';

  @override
  String get ldac660Kbps => 'LDAC 660 кбит/с';

  @override
  String get ldac990Kbps => 'LDAC 990 кбит/с';

  @override
  String get ldacAdaptive => 'LDAC Адаптивный';

  @override
  String get ldacBitsPerSample => 'Разрядность LDAC';

  @override
  String get leLsbLittleEndianSubslotLsb =>
      'LE-LSB — субслот little-endian, младший бит первым';

  @override
  String get leMsbLittleEndianSubslotMsb =>
      'LE-MSB — субслот little-endian, старший бит первым';

  @override
  String get leaveEmptyToKeepTheCurrent =>
      'Оставьте пустым, чтобы сохранить текущие учётные данные';

  @override
  String get leftBottom => 'Слева (снизу)';

  @override
  String get leftBottomButton => 'Левая (нижняя) кнопка';

  @override
  String get leftTop => 'Слева (сверху)';

  @override
  String get leftTopButton => 'Левая (верхняя) кнопка';

  @override
  String get length => 'Длина:';

  @override
  String lengthS(Object arg1) {
    return 'Длина $arg1 с';
  }

  @override
  String get letAndroidChooseTheBestCodec =>
      'Позволить Android выбрать лучший кодек';

  @override
  String get letAndroidChooseTheOutputDevice =>
      'Позволить Android выбрать устройство вывода';

  @override
  String get letAndroidNegotiateTheCodecAutomatically =>
      'Позволить Android согласовать кодек автоматически';

  @override
  String get letOboePickTheBestApi =>
      'Позволить Oboe выбрать лучший API: сначала AAudio, затем резервный OpenSL ES.';

  @override
  String get letSTakeAQuickTour =>
      'Давайте совершим короткую прогулку по вашему новому плееру.';

  @override
  String get libraryLabel => 'Медиатека';

  @override
  String get light => 'Светлая';

  @override
  String likedSongs(Object arg1) {
    return 'Понравившихся треков: $arg1';
  }

  @override
  String get likedSongsLiveHere => 'Здесь хранятся понравившиеся треки';

  @override
  String get likesAndReplaysBlendedTogether => 'Лайки и частые повторы вместе';

  @override
  String get limit => 'Лимит';

  @override
  String get limiter => 'Лимитер';

  @override
  String get limiterOff => 'Лимитер выкл.';

  @override
  String get limiterOn => 'Лимитер вкл.';

  @override
  String get line => 'Строка';

  @override
  String lineOf(Object arg1, Object arg2) {
    return 'Строка $arg1 из $arg2';
  }

  @override
  String lineOfWords(
    Object arg1,
    Object arg2,
    Object captured,
    Object segmentCount,
  ) {
    return 'Строка $arg1 из $arg2  ·  $captured/$segmentCount сл.';
  }

  @override
  String get lines => 'Линии';

  @override
  String lines2(Object arg1) {
    return 'Строк: $arg1';
  }

  @override
  String get linkReady => 'Ссылка готова';

  @override
  String linkedToThisSong(Object arg1) {
    return '«$arg1» привязано к этому треку.';
  }

  @override
  String get list => 'Список';

  @override
  String get listAvailableLocalAudioOutputDevices =>
      'Показать доступные локальные устройства вывода звука';

  @override
  String get listenbrainz => 'ListenBrainz';

  @override
  String get listenbrainzConnected => 'ListenBrainz подключён';

  @override
  String get listenbrainzConnected2 => 'ListenBrainz подключён!';

  @override
  String get listeningHours => 'Часы прослушивания';

  @override
  String listeningToByOnFlick(Object arg1, Object arg2) {
    return 'Слушаю $arg1 — $arg2 в Lokal';
  }

  @override
  String get littleEndianSubslotLsbFirstBits =>
      'Субслот little-endian, биты LSB-first';

  @override
  String get littleEndianSubslotMsbFirstBits =>
      'Субслот little-endian, биты MSB-first';

  @override
  String get livePreview => 'Живой предпросмотр';

  @override
  String get livingOrnament => 'Живой орнамент';

  @override
  String get loadAJsonOrTxtPreset => 'Загрузить пресет JSON или TXT';

  @override
  String get loadAnImpulseResponseForRoom =>
      'Загрузите импульсную характеристику для реверберации помещения, Crossfeed, кабинета или коррекции.';

  @override
  String get loadIr => 'Загрузить IR';

  @override
  String loadedIr(Object displayName) {
    return 'Загружен IR: $displayName';
  }

  @override
  String get loadingArtwork2 => 'Загрузка обложки…';

  @override
  String get loadingFavoritesRecentSessionsGenerated =>
      'Загрузка избранного, недавних сессий, миксов и плейлистов.';

  @override
  String get loadingReplay => 'Загрузка Replay';

  @override
  String get loadingSession => 'Загрузка сессии...';

  @override
  String get locked => 'Заблокировано';

  @override
  String get logFrequencyControl => 'Логарифмическое управление частотой';

  @override
  String get logs => 'Журналы';

  @override
  String get logsCopied => 'Журналы скопированы';

  @override
  String get longSongTitles => 'Длинные названия треков';

  @override
  String get look => 'Оформление';

  @override
  String get lookingForCoverArtFromMusicbrainz =>
      'Поиск обложки в MusicBrainz и Cover Art Archive.';

  @override
  String get lossless => ' Lossless';

  @override
  String get losslessQualityPreservedDuringConversion =>
      'Качество без потерь сохраняется при конвертации';

  @override
  String get lowAndHighFrequenciesScoopedMids =>
      'Низкие и высокие частоты, прибранная середина';

  @override
  String get lowFrequenciesOnly => 'Только низкие частоты';

  @override
  String get lowLatencyGoodQuality => 'Низкая задержка, хорошее качество';

  @override
  String get lowLatencyMode => 'Режим низкой задержки';

  @override
  String get lowPass => 'Фильтр НЧ';

  @override
  String get lowShelf => 'Полка НЧ';

  @override
  String get lrclib => 'LRCLib';

  @override
  String get lyric => 'Строка текста';

  @override
  String get lyrics => 'Текст песни';

  @override
  String get lyricsPreview => 'Предпросмотр текста';

  @override
  String get lyricsSavedFromLrclib => 'Текст песни сохранён из LRCLib.';

  @override
  String get lyricsSyncHelp => 'Справка по синхронизации текста';

  @override
  String get lyricsSyncStudio => 'Студия синхронизации текста';

  @override
  String get lyricsText => 'Текст песни';

  @override
  String m(Object arg1) {
    return '$arg1 мин';
  }

  @override
  String m2(Object arg1) {
    return '$arg1 мин';
  }

  @override
  String mAgo(Object arg1) {
    return '$arg1 мин назад';
  }

  @override
  String get madeForYou => 'Создано для вас';

  @override
  String get makeup => 'Компенсация';

  @override
  String get manualOrder => 'Ручной порядок';

  @override
  String get manualQueue => 'Ручная очередь';

  @override
  String get manufacturer => 'Производитель';

  @override
  String get mar => 'Мар';

  @override
  String get masterBypassed => 'Обход мастера';

  @override
  String matchByArtistAlbumAndTrack(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count файлов',
      many: '$count файлов',
      few: '$count файла',
      one: '$count файл',
    );
    return 'Сопоставить $_temp0 по исполнителю, альбому и длительности трека';
  }

  @override
  String get matchEqToYourHeadphoneModel =>
      'Подстроить EQ под модель ваших наушников';

  @override
  String get matchNavigation => 'Как у навигации';

  @override
  String get matches => 'Совпадения';

  @override
  String maxB(Object arg1) {
    return 'Макс. $arg1 Б';
  }

  @override
  String get maximumAudioQuality => 'Максимальное качество звука';

  @override
  String get may => 'Май';

  @override
  String mb(Object arg1) {
    return '$arg1 МБ';
  }

  @override
  String get medium => 'Средний';

  @override
  String get menu => 'Меню';

  @override
  String get metropolitan => 'Мегаполис';

  @override
  String mhz(Object arg1) {
    return '$arg1 МГц';
  }

  @override
  String get mid => 'Средние';

  @override
  String get midFrequenciesOnly => 'Только средние частоты';

  @override
  String get midnightCityDreams => 'Полуночные сны города';

  @override
  String get midnightSignal => 'Полуночный сигнал';

  @override
  String get milestone => 'Достижение';

  @override
  String get milestones => 'Достижения';

  @override
  String min(Object arg1) {
    return '$arg1 мин';
  }

  @override
  String get miniPlayer => 'Мини-плеер';

  @override
  String get miniPlayerAppearance => 'Внешний вид мини-плеера';

  @override
  String get miniPlayerDefaultsRestored =>
      'Настройки мини-плеера сброшены по умолчанию';

  @override
  String get miniPlayerHeight => 'Высота мини-плеера';

  @override
  String get miniPlayerLayout => 'Макет мини-плеера';

  @override
  String get minimal => 'Минималистичный';

  @override
  String get minimserverServiioKodi => 'MinimServer · Serviio · Kodi';

  @override
  String get mirrorTest => 'Зеркальный тест';

  @override
  String get mirrored => 'Зеркальный';

  @override
  String get mitLicenseCopyrightC2026Flick =>
      '\nMIT License\n\nCopyright (c) 2026 Flick Player Contributors\n\nPermission is hereby granted, free of charge, to any person obtaining a copy\nof this software and associated documentation files (the \"Software\"), to deal\nin the Software without restriction, including without limitation the rights\nto use, copy, modify, merge, publish, distribute, sublicense, and/or sell\ncopies of the Software, and to permit persons to whom the Software is\nfurnished to do so, subject to the following conditions:\n\nThe above copyright notice and this permission notice shall be included in all\ncopies or substantial portions of the Software.\n\nTHE SOFTWARE IS PROVIDED \"AS IS\", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR\nIMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,\nFITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE\nAUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER\nLIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,\nOUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE\nSOFTWARE.\n';

  @override
  String get mix => 'Микс';

  @override
  String mix2(Object arg1) {
    return 'Микс $arg1';
  }

  @override
  String get mixer => 'Микшер';

  @override
  String get mixerManagement => 'Управление микшером';

  @override
  String moAgo(Object arg1) {
    return '$arg1 мес. назад';
  }

  @override
  String get moderate => 'Умеренный';

  @override
  String get mono => 'Моно';

  @override
  String get monthly => 'Ежемесячно';

  @override
  String get more => 'Ещё';

  @override
  String more2(Object arg1, Object arg2) {
    return '$arg1 и ещё $arg2';
  }

  @override
  String get moreActions => 'Ещё действия';

  @override
  String get moreArtists => 'Другие исполнители';

  @override
  String get moreArtists2 => 'Другие исполнители';

  @override
  String get moreExportOptions => 'Другие варианты экспорта';

  @override
  String moreFrom(Object arg1) {
    return 'Ещё от $arg1';
  }

  @override
  String get moreFromArtist => 'Ещё от исполнителя';

  @override
  String moreTo(Object arg1, Object arg2) {
    return 'Ещё $arg1 до «$arg2»';
  }

  @override
  String moreToUnlock(Object remaining, Object unit) {
    return 'Ещё $remaining $unit для разблокировки.';
  }

  @override
  String get mostDlnaServersNeedNoPassword =>
      'Большинство серверов DLNA не требуют пароль';

  @override
  String get mostPlayed => 'Самые популярные';

  @override
  String mostReplayed(Object arg1) {
    return 'Чаще всего повторялось · $arg1';
  }

  @override
  String get motionArtRefreshed => 'Анимированная обложка обновлена';

  @override
  String get moveEveryStampedLyricForwardOr =>
      'Сдвинуть все размеченные строки текста вперёд или назад одновременно.';

  @override
  String get movement => 'Движение';

  @override
  String ms(Object arg1) {
    return '$arg1 мс';
  }

  @override
  String ms2(Object arg1) {
    return '$arg1 мс';
  }

  @override
  String ms3(Object arg1) {
    return '$arg1 мс';
  }

  @override
  String ms4(Object arg1) {
    return '$arg1 мс';
  }

  @override
  String ms5(Object arg1) {
    return '$arg1 мс';
  }

  @override
  String get multiFilterBands => 'Многофильтровые полосы';

  @override
  String musicFolders(Object arg1) {
    return 'Папок с музыкой: $arg1';
  }

  @override
  String get mute => 'Без звука';

  @override
  String my(Object arg1) {
    return 'Мой $arg1';
  }

  @override
  String nDb(Object arg1, Object arg2) {
    return '$arg1%\n$arg2 дБ';
  }

  @override
  String get nameAZ => 'Название (А–Я)';

  @override
  String narrow(Object amount) {
    return '$amount% уже';
  }

  @override
  String get nativeDsd => 'Нативный DSD';

  @override
  String get nativeDsdExperimental => 'Нативный DSD (экспериментально)';

  @override
  String get nativeDsdExperimentalMayBeBuggy =>
      'Нативный DSD — экспериментально (возможны сбои)';

  @override
  String get naturalEqualizerFeelResponsiveYetSmooth =>
      'Естественное поведение эквалайзера — отзывчивое и плавное';

  @override
  String get natureAmbient => 'Природный эмбиент';

  @override
  String get navidromeAirsonicGonic => 'Navidrome · Airsonic · Gonic';

  @override
  String get navigationBar => 'Панель навигации';

  @override
  String get needsMetadata => 'Требуются метаданные';

  @override
  String negotiated(Object arg1) {
    return 'Согласовано: $arg1';
  }

  @override
  String get neonNights => 'Неоновые ночи';

  @override
  String get neonSkyline => 'Неоновый горизонт';

  @override
  String get network => 'Сеть';

  @override
  String get networkSources => 'Сетевые источники';

  @override
  String neutral(Object amount) {
    return '$amount% нейтрально';
  }

  @override
  String get neverSynced => 'Никогда не синхронизировалось';

  @override
  String get next => 'Далее';

  @override
  String get nextSong => 'Следующий трек';

  @override
  String get nextSong2 => 'Следующий трек';

  @override
  String nextToGo(Object arg1, Object remaining, Object unit) {
    return 'Далее: $arg1 — осталось $remaining $unit';
  }

  @override
  String get nextcloudOwncloudSabredav => 'Nextcloud · ownCloud · SabreDAV';

  @override
  String get night => 'Ночь';

  @override
  String get no => 'Нет';

  @override
  String get noAlbumDataYet => 'Пока нет данных об альбомах';

  @override
  String get noAlbumsFound => 'Альбомы не найдены';

  @override
  String get noAppleMusicReleaseFoundTry =>
      'Релиз в Apple Music не найден. Попробуйте изменить имя исполнителя или название альбома и повторить поиск.';

  @override
  String get noArtistsFound => 'Исполнители не найдены';

  @override
  String noArtistsMatch(Object _searchQuery) {
    return 'Не найдено исполнителей по запросу «$_searchQuery»';
  }

  @override
  String get noCastingDevicesFoundMakeSure =>
      'Устройства трансляции не найдены. Убедитесь, что телефон и приёмник подключены к одной сети.';

  @override
  String get noCategoriesSelected => 'Категории не выбраны';

  @override
  String get noChangelogNotesForThisVersion =>
      'Для этой версии пока нет списка изменений.';

  @override
  String get noCustomPresetsYet => 'Пользовательских пресетов пока нет.';

  @override
  String get noDuplicatesFound => 'Дубликаты не найдены';

  @override
  String get noFavoritesYet => 'В избранном пока пусто';

  @override
  String get noFeaturedTrackYet => 'Главный трек пока не выбран';

  @override
  String get noFoldersAdded => 'Папки не добавлены';

  @override
  String get noHistoryYet => 'История пока пуста';

  @override
  String get noInternetConnectionPleaseCheckYour =>
      'Нет подключения к интернету. Проверьте сеть и повторите попытку.';

  @override
  String get noLogsYet => 'Журналов пока нет.';

  @override
  String get noLyricsFoundOnlineForThis =>
      'В сети не найден текст для этой песни.';

  @override
  String get noLyricsYet => 'Текста пока нет';

  @override
  String get noMatchFound => 'Совпадений не найдено';

  @override
  String get noMatches => 'Совпадений нет.';

  @override
  String noMatchesFor(Object _query) {
    return 'Нет совпадений для «$_query»';
  }

  @override
  String get noMatchesFound => 'Совпадения не найдены';

  @override
  String get noMatchesTryFewerWordsOr =>
      'Совпадений нет. Попробуйте сократить запрос или поискать в сети.';

  @override
  String get noMusicYet => 'Музыки пока нет';

  @override
  String get noNewAdditionsYet => 'Новых добавлений пока нет';

  @override
  String get noOnlineArtworkFound => 'Обложки в сети не найдены';

  @override
  String get noOutputDevicesAvailable => 'Нет доступных устройств вывода.';

  @override
  String get noPlaybackYet => 'Воспроизведений пока не было';

  @override
  String get noPlaylistsYet => 'Плейлистов пока нет';

  @override
  String get noPlaylistsYet2 => 'Плейлистов пока нет';

  @override
  String get noPlaylistsYetNcreateOneIn =>
      'Плейлистов пока нет.\nСоздайте его во вкладке «Плейлисты».';

  @override
  String get noRankingDataYet => 'Данных рейтинга пока нет';

  @override
  String noResultsFor(Object query) {
    return 'Нет результатов для «$query»';
  }

  @override
  String noResultsFoundFor(Object query) {
    return 'По запросу «$query» ничего не найдено.';
  }

  @override
  String get noRipData => 'Нет данных рипа';

  @override
  String get noScanResultsYet => 'Результатов сканирования пока нет';

  @override
  String get noServerPlaylistsFound => 'Плейлисты на сервере не найдены';

  @override
  String get noServersConnected => 'Серверы не подключены';

  @override
  String get noSongPlaying => 'Ничего не воспроизводится';

  @override
  String get noSongsFound => 'Треки не найдены';

  @override
  String get noSongsInThisPlaylist => 'В этом плейлисте нет треков';

  @override
  String get noUpcomingQueueItemsYet => 'В очереди пока нет следующих треков.';

  @override
  String get noUrbData => 'Нет данных URB';

  @override
  String get noUsbAudioDevicesFound => 'USB-аудиоустройства не найдены';

  @override
  String get noWordTimingYetAutoFill =>
      'Тайминг слов ещё не задан. Автозаполнение равномерно распределит слова для начала — или запишите их в режиме синхронизации слов.';

  @override
  String get none => 'Нет';

  @override
  String get notAnAlacFile => 'Не является файлом ALAC';

  @override
  String get notFoundOnlineTryADifferent =>
      'В сети не найдено. Попробуйте другое написание.';

  @override
  String get notHeld => 'Не удерживается';

  @override
  String get notRecommendedForNormalUsageDsd =>
      'Не рекомендуется для обычного использования. Воспроизведение DSD нестабильно и может вызывать искажения звука.';

  @override
  String get notRegistered => 'Не зарегистрировано';

  @override
  String get notSet => 'Не задано';

  @override
  String get notStampedYet => 'Метка ещё не задана';

  @override
  String get notVerified => 'Не проверено';

  @override
  String get notch => 'Режекторный';

  @override
  String get notchDepth => 'Глубина режекции';

  @override
  String get noticeableTintingFromAlbumArt =>
      'Заметный цветовой оттенок из обложки альбома.';

  @override
  String get nov => 'Ноя';

  @override
  String get now => 'Сейчас';

  @override
  String get nowPlaying => 'Сейчас играет';

  @override
  String get nowPlaying2 => 'Сейчас играет';

  @override
  String get numberOnArt => 'Номер на обложке';

  @override
  String get oauthSignInNoPasswordStored =>
      'Вход через OAuth; пароль здесь не хранится';

  @override
  String get oceanWaves => 'Океанские волны';

  @override
  String get oct => 'Окт';

  @override
  String get off => 'Выкл.';

  @override
  String get onAndroidTheStandardJustAudio =>
      'На Android стандартный тракт воспроизведения just_audio теперь применяет нативные аналоги эквалайзера, динамической обработки, баланса и пространственных эффектов на поддерживаемых устройствах. Движок Rust по-прежнему обеспечивает наиболее точную реализацию этих параметров, поэтому на Android результаты могут быть приблизительными.';

  @override
  String get onRepeat => 'На повторе';

  @override
  String get onlineResults => 'Результаты из сети';

  @override
  String get onlyLibraryEntriesAreRemovedYour =>
      'Удаляются только записи из медиатеки — аудиофайлы остаются на диске.';

  @override
  String get open => 'Открыть';

  @override
  String get openAndroidSettings => 'Открыть настройки Android';

  @override
  String get openBluetoothCodecSettings =>
      'Открыть настройки кодеков Bluetooth';

  @override
  String get openInAppleMusic => 'Открыть в Apple Music';

  @override
  String get openInBrowser => 'Открыть в браузере';

  @override
  String get openLibrary => 'Открыть медиатеку';

  @override
  String get openListenbrainzOrgSettings => 'Открыть listenbrainz.org/settings';

  @override
  String get openManual => 'Открыть руководство';

  @override
  String get openPlayer => 'Открыть плеер';

  @override
  String get openedFromLocker => 'Открыто из хранилища';

  @override
  String get openslEs => 'OpenSL ES';

  @override
  String get openslEsLegacy => 'OpenSL ES (устаревший)';

  @override
  String get orRemoveAllUsingRecommendedPicks =>
      'Или удалить всё по рекомендованному выбору';

  @override
  String get orbital => 'Орбитальный';

  @override
  String get otherPlaylists => 'Другие плейлисты';

  @override
  String get ourRustPoweredEngineCleanerSound =>
      'Наш движок на базе Rust. Более чистый звук и плавное воспроизведение — рекомендуется для повседневного прослушивания.';

  @override
  String get outlineTheMiniPlayer => 'Обводка мини-плеера';

  @override
  String get output => 'Вывод';

  @override
  String get outputDevice => 'Устройство вывода';

  @override
  String get outputMode => 'Режим вывода';

  @override
  String get outputRate => 'Частота вывода';

  @override
  String get overviewMetricsChooseUpTo3 => 'Показатели обзора · выберите до 3';

  @override
  String get paired => 'Сопряжено';

  @override
  String get parametric => 'Параметрический';

  @override
  String parametricBandsWithIndependentFrequency(Object arg1) {
    return '$arg1 параметрических полос с независимой настройкой частоты, усиления и добротности (Q). Нажмите для настройки.';
  }

  @override
  String get parametricEq => 'Параметрический эквалайзер';

  @override
  String get passthrough => 'Прямой вывод';

  @override
  String get password => 'Пароль';

  @override
  String get pasteOrTypeTheSongLyrics =>
      'Вставьте или введите текст песни — по одной строке на абзац';

  @override
  String get pasteYourListenbrainzToken => 'Вставьте ваш токен ListenBrainz';

  @override
  String get pause => 'Пауза';

  @override
  String get pauseOnBluetoothConnect => 'Пауза при подключении Bluetooth';

  @override
  String get pauseOnDisconnect => 'Пауза при отключении';

  @override
  String get pauseOnUsbDacAttach => 'Пауза при подключении USB DAC';

  @override
  String get pauseOnUsbDacDetach => 'Пауза при отключении USB DAC';

  @override
  String get pcmFrames => 'Кадры PCM';

  @override
  String get peakHour => 'Пиковый час';

  @override
  String get peaking => 'Пиковый';

  @override
  String get permission => 'Разрешение';

  @override
  String get personalPlaylist => 'Личный плейлист';

  @override
  String get phoneAndHeadsetVolumeAreIndependent =>
      'Громкость телефона и гарнитуры регулируется раздельно';

  @override
  String get phoneAndHeadsetVolumeAreLinked =>
      'Громкость телефона и гарнитуры синхронизирована';

  @override
  String get photoFraming => 'Кадрирование фото';

  @override
  String get pickALineWithLyrics => 'Выберите строку с текстом';

  @override
  String get pickALyricLineIn =>
      '1. Выберите строку текста во вкладке «Строки», затем перейдите в «Инструменты».\n2. Нажмите воспроизведение и нажимайте большую кнопку «Отметить слово» в момент звучания каждого слова — первое нажатие также задаст метку строки.\n3. Нажмите на блок слова, чтобы сдвинуть его, изменить тайминг или очистить.\n4. Строки, в которых отмечены все слова, сохраняются с пословным караоке-таймингом.';

  @override
  String get pickAgain => 'Выбрать снова';

  @override
  String get pickImage => 'Выбрать изображение';

  @override
  String get pickUpExactlyWhereYourLast =>
      'Продолжите точно с того места, на котором остановились в прошлый раз.';

  @override
  String get pinchApartNarrowerHigherQNpinch =>
      'Развести пальцы = уже (выше Q)\nСвести пальцы = шире (ниже Q)';

  @override
  String get pitch => 'Тональность';

  @override
  String pitchSemitones(int semitones) {
    String _temp0 = intl.Intl.pluralLogic(
      semitones,
      locale: localeName,
      other: '$semitones полутона',
      many: '$semitones полутонов',
      few: '$semitones полутона',
      one: '$semitones полутон',
    );
    return '$_temp0';
  }

  @override
  String get plain => 'Обычный';

  @override
  String get plainText => 'Обычный текст';

  @override
  String get play => 'Воспроизвести';

  @override
  String get playAFewSongsAndThis =>
      'Послушайте несколько треков, и на этой странице появятся миксы, исполнители и быстрые переходы.';

  @override
  String get playAFewTracksTodayTo =>
      'Послушайте несколько треков сегодня, чтобы сформировать дневной итог.';

  @override
  String get playAgain => 'Послушать снова';

  @override
  String get playBadges => 'Значки прослушиваний';

  @override
  String get playCategoriesInRandomOrderTracks =>
      'Воспроизводить категории в случайном порядке, а треки — по порядку';

  @override
  String get playInOrder => 'Воспроизводить по порядку';

  @override
  String get playNext => 'Воспроизвести следующим';

  @override
  String get playbackContinuesWhenABluetoothDevice =>
      'Воспроизведение продолжается при подключении Bluetooth-устройства';

  @override
  String get playbackContinuesWhenAUsbDac =>
      'Воспроизведение продолжается при подключении USB DAC';

  @override
  String get playbackContinuesWhenAUsbDac2 =>
      'Воспроизведение продолжается при отключении USB DAC';

  @override
  String get playbackContinuesWhenAudioOutput =>
      'Воспроизведение продолжается при отключении устройства вывода';

  @override
  String get playbackEngine => 'Движок воспроизведения';

  @override
  String get playbackIsUsingAndroidManagedOutput =>
      'Воспроизведение идёт через системный вывод Android и может подвергаться ресемплингу.';

  @override
  String get playbackIsUsingTheStandardAndroid =>
      'Воспроизведение использует стандартный тракт вывода Android.';

  @override
  String get playbackModeWillUpdateAfterThe =>
      'Режим воспроизведения обновится после следующей смены маршрута или перезапуска воспроизведения.';

  @override
  String get playbackPath => 'Тракт воспроизведения';

  @override
  String get playbackPausesWhenABluetoothAudio =>
      'Воспроизведение ставится на паузу при подключении Bluetooth-аудиоустройства';

  @override
  String get playbackPausesWhenAUsbDac =>
      'Воспроизведение ставится на паузу при подключении USB DAC';

  @override
  String get playbackPausesWhenAUsbDac2 =>
      'Воспроизведение ставится на паузу при физическом отключении USB DAC';

  @override
  String get playbackPausesWhenBluetoothOrHeadphones =>
      'Воспроизведение ставится на паузу при отключении Bluetooth или наушников';

  @override
  String get playbackResumesWhenADeviceReconnects =>
      'Воспроизведение возобновляется при повторном подключении устройства в течение 30 секунд';

  @override
  String get playbackSpeed => 'Скорость воспроизведения';

  @override
  String played(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Прослушано $count треков',
      many: 'Прослушано $count треков',
      few: 'Прослушано $count трека',
      one: 'Прослушан $count трек',
    );
    return '$_temp0';
  }

  @override
  String get playerLayout => 'Макет плеера';

  @override
  String playlist(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count плейлистов',
      many: '$count плейлистов',
      few: '$count плейлиста',
      one: '$count плейлист',
    );
    return '$_temp0';
  }

  @override
  String get playlist2 => 'Плейлист';

  @override
  String playlistCreated(Object arg1) {
    return 'Плейлист «$arg1» создан';
  }

  @override
  String get playlistName => 'Название плейлиста';

  @override
  String get playlists => 'Плейлисты';

  @override
  String plays(Object arg1) {
    return 'Прослушиваний: $arg1';
  }

  @override
  String plays2(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count прослушиваний',
      many: '$count прослушиваний',
      few: '$count прослушивания',
      one: '$count прослушивание',
    );
    return '$_temp0';
  }

  @override
  String get playsInRotation => 'прослушиваний в ротации';

  @override
  String get pleaseEnterAPlaylistName => 'Введите название плейлиста';

  @override
  String get pleaseEnterYourListenbrainzUserToken =>
      'Введите ваш пользовательский токен ListenBrainz.';

  @override
  String posterPreviewPlays(Object arg1, Object arg2) {
    return 'Предпросмотр постера «$arg1». Прослушиваний: $arg2.';
  }

  @override
  String get preamp => 'Предусилитель';

  @override
  String get preloadingAudio3 => 'Предзагрузка аудио';

  @override
  String get preparing => 'Подготовка…';

  @override
  String get presence => 'Присутствие';

  @override
  String preset(Object activePresetName) {
    return 'Пресет: $activePresetName';
  }

  @override
  String get presetImportedWithAdjustments =>
      'Пресет импортирован с корректировками';

  @override
  String get presetName => 'Название пресета';

  @override
  String get presets => 'Пресеты';

  @override
  String get preview => 'Предпросмотр';

  @override
  String get previewUse => 'Просмотреть и применить';

  @override
  String get previousSong => 'Предыдущий трек';

  @override
  String get previousSong2 => 'Предыдущий трек';

  @override
  String get prewarming => 'Прогрев';

  @override
  String get prioritiseConnectionStability =>
      'Приоритет стабильности соединения';

  @override
  String get processingLive => 'Обработка в реальном времени';

  @override
  String get product => 'Продукт';

  @override
  String get productId => 'ID продукта';

  @override
  String get progress => 'Прогресс';

  @override
  String get protocol => 'Протокол';

  @override
  String get pulledFromYourLateSessionPlays =>
      'Подобрано из ваших поздних прослушиваний';

  @override
  String get purple => 'Фиолетовый';

  @override
  String get queue => 'Очередь';

  @override
  String queue2(Object count) {
    return 'Очередь ($count)';
  }

  @override
  String get queueIsEmpty => 'Очередь пуста';

  @override
  String queued(Object arg1) {
    return 'В очереди: «$arg1»';
  }

  @override
  String queuedSongs(Object arg1) {
    return 'Добавлено в очередь треков: $arg1';
  }

  @override
  String queuedSongs3(Object arg1) {
    return 'Добавлено в очередь треков: $arg1';
  }

  @override
  String get quickActions => 'Быстрые действия';

  @override
  String get random => 'Случайно';

  @override
  String get rating => 'Рейтинг';

  @override
  String get ratio => 'Степень сжатия';

  @override
  String get rawDsdStreamToDacRequires =>
      'Необработанный поток DSD на ЦАП. Требуется аппаратная поддержка ENCODING_DSD; иначе автоматически выполняется переход на DoP или PCM.';

  @override
  String get rawPcm => '→ Чистый PCM';

  @override
  String get readMode => 'Режим чтения';

  @override
  String get readingTheCoverColors => 'Анализ цветов обложки…';

  @override
  String readyToRemoveSongKeepingIn(int count, Object kept) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count треков',
      many: '$count треков',
      few: '$count трека',
      one: '$count трек',
    );
    return 'Готово к удалению: $_temp0 — всего останется $kept.';
  }

  @override
  String recapSavedAs(Object format) {
    return 'Итог сохранён в формате $format';
  }

  @override
  String recentPicksOnHand(Object arg1) {
    return 'Недавних подборок под рукой: $arg1';
  }

  @override
  String get recentlyAdded => 'Недавно добавленные';

  @override
  String get recentlyAddedTracksWaitingForMore =>
      'Недавно добавленные треки, ждущие больше прослушиваний.';

  @override
  String get recentlyPlayed => 'Недавно прослушанные';

  @override
  String get recommended => 'Рекомендуется';

  @override
  String get recommendedOnly => 'Только рекомендованные';

  @override
  String get reconnectAttempts => 'Попытки переподключения';

  @override
  String get reconnectNow => 'Переподключить сейчас';

  @override
  String get reconnectionFailed => 'Не удалось переподключиться';

  @override
  String get reconnectionSuccessful => 'Переподключение выполнено';

  @override
  String get recorded => 'Записано';

  @override
  String get refreshAppleMusic => 'Обновить Apple Music';

  @override
  String get refreshDevices => 'Обновить устройства';

  @override
  String get refreshDevices2 => 'Обновить устройства';

  @override
  String get refreshMotionArt => 'Обновить анимированную обложку';

  @override
  String get refreshOutputs => 'Обновить устройства вывода';

  @override
  String get refreshingAppleMusicData => 'Обновление данных Apple Music';

  @override
  String get registeredNotClaimed => 'Зарегистрировано, не захвачено';

  @override
  String get reinitializingPlayback =>
      'Повторная инициализация воспроизведения…';

  @override
  String get release => 'Восстановление';

  @override
  String get remove => 'Удалить';

  @override
  String get removeAll => 'Удалить всё';

  @override
  String get removeAllWithBestPicks => 'Удалить всё, оставив лучшие версии?';

  @override
  String get removeCustomArt => 'Удалить пользовательскую обложку';

  @override
  String removeDuplicates2(Object toRemove) {
    return 'Удалить дубликаты ($toRemove)?';
  }

  @override
  String removeDuplicates3(Object toRemove) {
    return 'Удалить дубликаты ($toRemove)';
  }

  @override
  String get removeFromFavorites => 'Удалить из избранного';

  @override
  String get removeFromFavorites2 => 'Удалить из избранного';

  @override
  String get removeFromLibrary => 'Удалить из медиатеки';

  @override
  String get removeFromPlaylist => 'Удалить из плейлиста';

  @override
  String get removeSelected => 'Удалить выбранные';

  @override
  String get removeServer => 'Удалить сервер?';

  @override
  String get removeServer2 => 'Удалить сервер';

  @override
  String get removeTheDatabaseEntriesOrDelete =>
      'Удалить записи из базы данных или удалить файлы с устройства. Это действие нельзя отменить.';

  @override
  String get removeTheDatabaseEntryOrDelete =>
      'Удалить запись из базы данных или удалить файл с устройства. Это действие нельзя отменить.';

  @override
  String get removeTheseSongsFromYourLibrary =>
      'Удалить эти треки из медиатеки. Файлы на устройстве не будут затронуты.';

  @override
  String get removeThisSongFromYourLibrary =>
      'Удалить этот трек из медиатеки. Файл на устройстве не будет затронут.';

  @override
  String removedCustomAlbumArtFor(Object arg1) {
    return 'Пользовательская обложка для «$arg1» удалена.';
  }

  @override
  String removedCustomAlbumArtFor2(Object arg1) {
    return 'Пользовательская обложка для «$arg1» удалена.';
  }

  @override
  String removedDuplicatesKept(Object arg1, Object arg2) {
    return 'Удалено дубликатов: $arg1 — оставлено: $arg2.';
  }

  @override
  String removedFromFavorites(Object arg1) {
    return '«$arg1» удалён из избранного';
  }

  @override
  String removedFromFavorites2(Object arg1) {
    return 'Удалено из избранного: $arg1';
  }

  @override
  String get removedFromFavorites3 => 'Удалено из избранного';

  @override
  String removedFromLibrary(Object arg1) {
    return '«$arg1» удалён из медиатеки';
  }

  @override
  String removedSongsFromFavorites(Object arg1) {
    return 'Удалено треков из избранного: $arg1';
  }

  @override
  String removedSongsFromLibrary(Object arg1) {
    return 'Удалено треков из медиатеки: $arg1';
  }

  @override
  String get removing => 'Удаление…';

  @override
  String get removingDuplicates => 'Удаление дубликатов…';

  @override
  String get rename => 'Переименовать';

  @override
  String get renamePreset => 'Переименовать пресет';

  @override
  String get reorderFilterAndShuffleFromThis =>
      'Меняйте порядок, фильтруйте и перемешивайте прямо из этого заголовка.';

  @override
  String repeat(Object arg1) {
    return 'Повтор: $arg1';
  }

  @override
  String get repeatMode => 'Режим повтора';

  @override
  String get repeatRewind => 'Повтор хитов';

  @override
  String get replaceAlbumNameWithAVerified =>
      'Заменять название альбома подтверждённым значком bit-perfect при bit-perfect воспроизведении';

  @override
  String get replay => 'Replay';

  @override
  String get replayCouldnTLoad => 'Не удалось загрузить Replay.';

  @override
  String get replayStudio => 'Replay Studio';

  @override
  String get reportedOutputRate => 'Заявленная частота вывода';

  @override
  String get requestedOutputRate => 'Запрошенная частота вывода';

  @override
  String get requiredToDetectDevicesCodecsAnd =>
      'Требуется для определения устройств, кодеков и уровня заряда';

  @override
  String get resampler => 'Ресемплер';

  @override
  String get reset => 'Сбросить';

  @override
  String get resetArtwork => 'Сбросить обложку';

  @override
  String get resetArtworkDescription =>
      'Повторно определить обложку из файлов этого альбома? Автоматически найденные обложки будут заменены встроенными в файлы; пользовательская обложка сохранится.';

  @override
  String resetArtworkFor(Object arg1) {
    return 'Обложка для «$arg1» сброшена.';
  }

  @override
  String resetArtworkFor2(Object arg1) {
    return 'Обложка для «$arg1» сброшена.';
  }

  @override
  String get resetCardDesign => 'Сбросить оформление карточки';

  @override
  String get resetDeclinedUsbDacs => 'Сбросить отклонённые USB DAC';

  @override
  String get resetDynamics => 'Сбросить динамику';

  @override
  String get resetFx => 'Сбросить эффекты';

  @override
  String get resetMiniPlayerToDefaults => 'Сбросить мини-плеер по умолчанию';

  @override
  String get resetPreferences => 'Сбросить настройки';

  @override
  String get resetTo0Db => 'Сбросить до 0 дБ';

  @override
  String get resolution => 'Разрешение';

  @override
  String get resonance => 'Резонанс';

  @override
  String get restart => 'Перезапустить';

  @override
  String get restartRequired => 'Требуется перезапуск';

  @override
  String get restartTheAppToApplyPlayback =>
      'Перезапустите приложение, чтобы применить изменения воспроизведения.';

  @override
  String get restartYourDeviceToApplyOutput =>
      'Перезагрузите устройство, чтобы применить изменения формата вывода.';

  @override
  String get restartingFlick => 'Перезапуск Lokal';

  @override
  String results(Object arg1) {
    return 'Результаты ($arg1)';
  }

  @override
  String get resumeAFamiliarFavoriteOrShuffle =>
      'Вернитесь к знакомому любимому треку или перемешайте один из миксов, собранных по вашим прослушиваниям.';

  @override
  String get resumeOnReconnect => 'Возобновлять при переподключении';

  @override
  String get retakePhoto => 'Переснять фото';

  @override
  String get retroFuture => 'Ретро-будущее';

  @override
  String get retry => 'Повторить';

  @override
  String get reviewBeforeYouClean => 'Проверьте перед очисткой';

  @override
  String get rightBottom => 'Справа (внизу)';

  @override
  String get rightBottomButton => 'Правая (нижняя) кнопка';

  @override
  String get rightTop => 'Справа (вверху)';

  @override
  String get rightTopButton => 'Правая (верхняя) кнопка';

  @override
  String get ripSource => 'Источник рипа';

  @override
  String get root => 'Корень';

  @override
  String get rotationSeek => 'перемотка вращением';

  @override
  String get roundedAlbumArtCardWithA =>
      'Скруглённая карточка обложки на размытом фоне обложки альбома.';

  @override
  String get route => 'Маршрут';

  @override
  String get routesBluetoothThroughTheHiRes =>
      'Направляет звук Bluetooth через Hi-Res движок Rust';

  @override
  String get routesBluetoothThroughTheRustEngine =>
      'Направляет звук Bluetooth через движок Rust';

  @override
  String get rustViaOboe => 'Rust через Oboe';

  @override
  String get rustViaOboeHighRes => 'Rust через Oboe (Hi-Res)';

  @override
  String s(Object arg1) {
    return '$arg1 с';
  }

  @override
  String sAgo(Object arg1) {
    return '$arg1 с назад';
  }

  @override
  String get sambaWindowsShareTransportPending => 'Samba · Общие папки Windows';

  @override
  String get sampleArtist => 'Пример исполнителя';

  @override
  String get samplePreview => 'Пример предпросмотра';

  @override
  String get sampleRate => 'Частота дискретизации';

  @override
  String get sampleRate2 => 'Частота дискретизации';

  @override
  String get sampleRates => 'Частоты дискретизации';

  @override
  String get sampleSongPreviewOnly => 'Пример трека · только предпросмотр';

  @override
  String get samples => 'Семплы';

  @override
  String get save => 'Сохранить';

  @override
  String get saveAsText => 'Сохранить как текст';

  @override
  String get saveChanges => 'Сохранить изменения';

  @override
  String get saveConnect => 'Сохранить и подключить';

  @override
  String get saveCreatesAnLrcFileIf =>
      'При сохранении создаётся файл `.lrc`. Если для части строк ещё нет временных меток, Lokal заполнит их автоматически, чтобы файл оставался рабочим. Строки с полностью размеченными словами экспортируются с пословным караоке-таймингом.';

  @override
  String get saveCurrentAsPreset => 'Сохранить текущие настройки как пресет';

  @override
  String get saveCustomizeReplay => 'Сохранить / настроить Replay';

  @override
  String get saveInFlick => 'Сохранить в Lokal';

  @override
  String get saveLogs => 'Сохранить журналы';

  @override
  String get saveLrcFile => 'Сохранить файл LRC';

  @override
  String get saveLrcFile2 => 'Сохранить файл LRC';

  @override
  String get saveLyrics => 'Сохранить текст';

  @override
  String get savePng => 'Сохранить PNG';

  @override
  String get savePreset => 'Сохранить пресет';

  @override
  String get saveTheCurrentEqAsJson =>
      'Сохранить текущий эквалайзер в формате JSON или TXT';

  @override
  String get saved => 'Сохранено';

  @override
  String get savedAgain => 'Сохранено · снова';

  @override
  String get savedAndVerified => 'Сохранено и проверено';

  @override
  String savedCollections(Object playlistCount) {
    return 'Сохранённых коллекций: $playlistCount';
  }

  @override
  String get savedLyricsAndLinkedThemTo =>
      'Текст сохранён и привязан к этому треку.';

  @override
  String get savedLyricsBesideTheSongAs =>
      'Текст сохранён рядом с треком в виде файла `.lrc`.';

  @override
  String get savedLyricsToTheChosenLocation =>
      'Текст сохранён в выбранное расположение.';

  @override
  String get savedPlaylistsAndQuickJumpsInto =>
      'Сохранённые плейлисты и быстрые переходы по вашей медиатеке.';

  @override
  String get savedToGallery => 'Сохранено в галерею';

  @override
  String savedToNNNshareIt(Object path) {
    return 'Сохранено в:\n$path\n\nПоделиться сейчас?';
  }

  @override
  String savedToYourGallery(Object arg1) {
    return '«$arg1» сохранено в галерею';
  }

  @override
  String get savedVerificationPending => 'Сохранено (ожидает проверки)';

  @override
  String get saving => 'Сохранение...';

  @override
  String get scaleTheAlbumArtCard => 'Масштаб карточки обложки';

  @override
  String get scaleTheFullViewAlbumArt =>
      'Масштаб карточки обложки в полноэкранном режиме';

  @override
  String get scalesWithWidgetSizeAutomatically =>
      'Автоматически подстраивается под размер виджета';

  @override
  String get scanAgain => 'Сканировать снова';

  @override
  String get scanForDevices => 'Поиск устройств';

  @override
  String get scanProgress => 'Ход сканирования';

  @override
  String get scanningForDuplicates => 'Поиск дубликатов…';

  @override
  String get scanningYourLibrary => 'Сканирование медиатеки…';

  @override
  String get scroll => 'Прокрутка';

  @override
  String get scrollForMore => 'Прокрутите, чтобы увидеть больше';

  @override
  String get scrollingPausesWhenReducedMotionIs =>
      'Прокрутка приостанавливается при включённом уменьшении движения';

  @override
  String get search => 'Поиск';

  @override
  String get searchAcrossSongsArtistsAndAlbums =>
      'Мгновенный поиск по трекам, исполнителям и альбомам.';

  @override
  String get searchAgain => 'Искать снова';

  @override
  String get searchArtistTitle => 'Поиск исполнителя и названия...';

  @override
  String get searchArtists => 'Поиск исполнителей...';

  @override
  String get searchFailed => 'Ошибка поиска';

  @override
  String searchFailed2(Object e) {
    return 'Ошибка поиска: $e';
  }

  @override
  String get searchHeadphones => 'Поиск наушников…';

  @override
  String searchModelCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count моделей',
      many: '$count моделей',
      few: '$count моделей',
      one: '$count модели',
    );
    return 'Поиск среди $_temp0…';
  }

  @override
  String get searchOnline => 'Искать в сети';

  @override
  String get searchOnline2 => 'Искать в сети';

  @override
  String get searchOnlineCreateYourOwnSynced =>
      'Найдите в сети, создайте собственный синхронизированный текст или импортируйте готовый файл.';

  @override
  String get searchOnlineLyrics => 'Поиск текстов в сети';

  @override
  String get searchSongsArtists => 'Поиск треков, исполнителей...';

  @override
  String get searchSongsArtistsAlbums =>
      'Поиск треков, исполнителей, альбомов...';

  @override
  String get searchTheManual => 'Поиск по руководству...';

  @override
  String get searchYourLibrary => 'Поиск по медиатеке';

  @override
  String get searching => 'Поиск…';

  @override
  String get searchingOnline => 'Поиск в сети';

  @override
  String get searchingTheLocalNetwork => 'Поиск в локальной сети…';

  @override
  String get seeAll => 'Показать все';

  @override
  String seeAll2(Object count) {
    return 'Показать все ($count)';
  }

  @override
  String get select => 'Выбрать';

  @override
  String get selectALineAndEdit =>
      '1. Выберите строку и отредактируйте её временную метку вручную или нажмите «Текущее время».\n2. На шкале слов перетаскивайте границу, чтобы растянуть или сжать предшествующий сегмент — шаг привязки 10 мс.\n3. Нажимайте на буквы в инспекторе, чтобы разделить слово на слоги с отдельным таймингом (для переменного темпа), а затем двигайте их границы.\n4. Перетащите последнюю границу (или используйте «Длина ±»), чтобы пересчитать время следующей строки. Используйте «Автозаполнение» для равномерного распределения слов.\n5. Используйте элементы сдвига, чтобы переместить все размеченные строки одновременно.\n6. Нажмите «Сохранить», чтобы создать итоговый файл `.lrc`.';

  @override
  String get selectARelease => 'Выберите релиз';

  @override
  String get selectAll => 'Выбрать все';

  @override
  String get selectAll2 => 'Выбрать все';

  @override
  String get selectDevice => 'Выберите устройство';

  @override
  String selected(Object count) {
    return 'Выбрано: $count';
  }

  @override
  String selectedOfSong(Object selected, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count треков',
      many: '$count треков',
      few: '$count треков',
      one: '$count трека',
    );
    return 'Выбрано $selected из $_temp0';
  }

  @override
  String get sep => 'Сен';

  @override
  String get separateFromNavBar => 'Отделить от панели навигации';

  @override
  String get separateTheMiniPlayerToCustomize =>
      'Отделите мини-плеер, чтобы настроить его ширину и отступ. Ваши настройки сохраняются при объединении.';

  @override
  String get serialNumber => 'Серийный номер';

  @override
  String serverPlaylistSyncFailed(Object e) {
    return 'Ошибка синхронизации плейлистов сервера: $e';
  }

  @override
  String get serverUrl => 'URL сервера';

  @override
  String get session => 'Сессия';

  @override
  String get setAlbumArt => 'Задать обложку альбома';

  @override
  String get setToNow => 'Задать текущее время';

  @override
  String get settings => 'Настройки';

  @override
  String get shadow => 'Тень';

  @override
  String get shadowJazz => 'Теневой джаз';

  @override
  String get share => 'Поделиться';

  @override
  String shareFailed(Object e) {
    return 'Не удалось поделиться: $e';
  }

  @override
  String get sharedSecret => 'Общий секрет';

  @override
  String get shiftMetadataTextUpOrDown =>
      'Сдвинуть текст метаданных вверх или вниз';

  @override
  String get shiftOnlyTheAlbumArtUp =>
      'Сдвинуть вверх или вниз только обложку альбома';

  @override
  String get shiftOnlyTheSongDetailsUp =>
      'Сдвинуть вверх или вниз только сведения о треке';

  @override
  String get showAThinPlaybackProgressLine =>
      'Показывать тонкую полосу прогресса воспроизведения';

  @override
  String get showAlbum => 'Показывать альбом';

  @override
  String get showAlbum2 => 'Показывать альбом';

  @override
  String get showAlbumArtwork => 'Показывать обложку альбома.';

  @override
  String get showAlbumArtworkOnTheMini =>
      'Показывать обложку альбома в мини-плеере';

  @override
  String get showArtist => 'Показывать исполнителя';

  @override
  String get showArtist2 => 'Показывать исполнителя';

  @override
  String get showArtistBelowSongTitle =>
      'Показывать исполнителя под названием трека';

  @override
  String get showFileInfo => 'Показывать сведения о файле';

  @override
  String get showFileInfo2 => 'Показывать сведения о файле';

  @override
  String get showFrame => 'Показывать рамку';

  @override
  String get showFrame2 => 'Показывать рамку';

  @override
  String get showLess => 'Свернуть';

  @override
  String get showLyrics => 'Показать текст';

  @override
  String get showMore => 'Показать больше';

  @override
  String get showOtherArtistsOnAlbumPages =>
      'Показывать других исполнителей на страницах альбомов';

  @override
  String get showPassword => 'Показать пароль';

  @override
  String get showRelatedAlbumsOnAlbumPages =>
      'Показывать похожие альбомы на страницах альбомов';

  @override
  String get showTheArtistBelowTheSong =>
      'Показывать исполнителя под названием трека';

  @override
  String get showTheAudioVisualizerOffSaves =>
      'Показывать аудиовизуализатор (выключение экономит заряд)';

  @override
  String get showTheGlassFrameAroundAlbum =>
      'Показывать стеклянную рамку вокруг обложки';

  @override
  String get showTheMiniPlayerAsIts =>
      'Отображать мини-плеер отдельной панелью над кнопками';

  @override
  String get showTheNumberOverBlurredArt =>
      'Показывать номер поверх размытой обложки.';

  @override
  String get showTheTrackNumber => 'Показывать номер трека.';

  @override
  String get showTitle => 'Показывать название';

  @override
  String get showTitle2 => 'Показывать название';

  @override
  String get showVerboseAudioDiagnosticsAndEngine =>
      'Показывать подробную аудиодиагностику и журналы трассировки движка и сессии.';

  @override
  String get showVisualizer => 'Показывать визуализатор';

  @override
  String showingAllAlbums(Object totalCount) {
    return 'Показаны все альбомы ($totalCount)';
  }

  @override
  String showingOfAlbums(Object visibleCount, Object totalCount) {
    return 'Показано альбомов: $visibleCount из $totalCount';
  }

  @override
  String get showingYourLastLoadedReplay =>
      'Показан последний загруженный Replay.';

  @override
  String get shownWhenThereIsRoomBeside =>
      'Отображается, если рядом с элементами управления хватает места';

  @override
  String get showsWhatSPlayingTapTo =>
      'Показывает текущий трек. Нажмите, чтобы открыть полный плеер.';

  @override
  String get shuffle => 'Перемешать';

  @override
  String shuffle2(Object arg1) {
    return 'Перемешивание: $arg1';
  }

  @override
  String get shuffleFavorites => 'Перемешать избранное';

  @override
  String get shuffleMode => 'Режим перемешивания';

  @override
  String get shuffleSongsAndJumpBetweenCategories =>
      'Перемешивать треки и переключаться между категориями';

  @override
  String get shuffleSongsInCurrentList => 'Перемешивать треки в текущем списке';

  @override
  String get signInFailedRetry => 'Ошибка входа — повторить';

  @override
  String get signInWithTidal => 'Войти через Tidal';

  @override
  String get signInWithYourAccountHifi =>
      'Войдите со своим аккаунтом · HiFi lossless';

  @override
  String get signInWithYourOwnTidal =>
      'Войдите в свой аккаунт Tidal. HiFi lossless (FLAC/ALAC) воспроизводится через bit-perfect движок; HiRes/MQA и Atmos ограничены со стороны Tidal и вместо воспроизведения покажут ошибку.';

  @override
  String get signal => 'Сигнал';

  @override
  String get signalAccurateUnverified => 'AccurateRip не подтверждён';

  @override
  String get signalAccurateVerified => 'AccurateRip подтверждён в логе';

  @override
  String get signalAltSetting => 'Alt-настройка';

  @override
  String get signalBufferCapacity => 'Ёмкость буфера';

  @override
  String get signalBufferFill => 'Заполнение буфера';

  @override
  String get signalBufferOccupancy => 'Заполненность буфера при открытии';

  @override
  String get signalBufferTarget => 'Целевой размер буфера';

  @override
  String get signalCopyCrc => 'CRC копии';

  @override
  String get signalCrcCannotCompare => 'Невозможно сравнить';

  @override
  String get signalCrcComparison => 'Сравнение CRC';

  @override
  String get signalCrcMatch => 'Совпадает';

  @override
  String get signalCrcMismatch => 'Не совпадает';

  @override
  String get signalDriftFromTarget => 'Отклонение от цели';

  @override
  String get signalDsdBitRate => 'Битрейт DSD';

  @override
  String get signalFileFormat => 'Формат файла';

  @override
  String get signalFramesPerPacket => 'Фреймов / пакет';

  @override
  String get signalMaxPacket => 'Макс. пакет';

  @override
  String get signalNoRipDescription =>
      'Для этого трека не найдено данных о рипе или проверке.';

  @override
  String get signalNotReported => 'Нет данных';

  @override
  String get signalNotVerified => 'Не проверено';

  @override
  String get signalRecordingUnavailable => 'История рипа недоступна';

  @override
  String get signalRipDescription =>
      'Сведения из журнала рипа, а не этап текущего тракта воспроизведения.';

  @override
  String get signalRipProvenance => 'Происхождение рипа';

  @override
  String get signalRipper => 'Риппер';

  @override
  String get signalServiceInterval => 'Интервал обслуживания';

  @override
  String get signalSnapshot => 'Снимок';

  @override
  String get signalSnapshotAtOpen => 'Снимок при открытии';

  @override
  String get signalSourceDescription =>
      'Свойства исходного файла, а не выходного потока, отправляемого на устройство.';

  @override
  String get signalSourceDetails => 'Параметры исходного формата';

  @override
  String get signalSubslot => 'Подслот';

  @override
  String get signalSyncType => 'Тип синхронизации';

  @override
  String get signalTarget => 'цель';

  @override
  String get signalTestCrc => 'Тестовый CRC';

  @override
  String get signalTransportFormat => 'Транспорт';

  @override
  String get signalUnderruns => 'Опустошения буфера';

  @override
  String get signalUsageType => 'Тип использования';

  @override
  String get signalUsbDescription =>
      'Параметры транспорта на момент открытия этого окна. Это не трассировка пакетов в реальном времени.';

  @override
  String get signalUsbMissingDescription =>
      'Сведения URB отображаются только для прямого USB-тракта. Активность передачи не предполагается.';

  @override
  String get signalUsbTransport => 'USB-транспорт';

  @override
  String get signalUsbUnavailable => 'Данные USB-транспорта недоступны';

  @override
  String get signalVerificationMissing => 'Проверка не указана';

  @override
  String get signalVerifiedInLog => 'Проверено по журналу';

  @override
  String get signedIn => 'Вход выполнен';

  @override
  String get silkySmoothBZierCurvesFluid =>
      'Плавные кривые Безье — текучие и органичные';

  @override
  String get similarArtists => 'Похожие исполнители';

  @override
  String get simple => 'Простой';

  @override
  String get simpleMode => 'Простой режим';

  @override
  String get single => 'Сингл';

  @override
  String get size => 'Размер';

  @override
  String get skip => 'Пропустить';

  @override
  String skippedUnmatchedEntr(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Пропущено $count несопоставленных записей',
      many: 'Пропущено $count несопоставленных записей',
      few: 'Пропущено $count несопоставленные записи',
      one: 'Пропущена $count несопоставленная запись',
    );
    return ' $_temp0.';
  }

  @override
  String get sleepTimer => 'Таймер сна';

  @override
  String get sleepTimer2 => 'Таймер сна';

  @override
  String get sleeves => 'Конверты';

  @override
  String get slope => 'Крутизна';

  @override
  String get smbSharesCanBeAddedNow =>
      'Сетевые папки SMB2/3 подключаются через встроенный клиент. Введите URL ресурса (smb://host/share) и войдите, если сервер запросит авторизацию.';

  @override
  String get smooth => 'Плавный';

  @override
  String get smoothsPeaksAndRaisesBodyBefore =>
      'Сглаживает пики и добавляет плотности до того, как лимитер сдержит транзиенты.';

  @override
  String get snappy => 'Резкий';

  @override
  String get softwareAppControlled => 'Программная (управляется приложением)';

  @override
  String get solid => 'Сплошной';

  @override
  String get someOnlineFeaturesMayNotWork =>
      '  ·  Некоторые онлайн-функции могут не работать';

  @override
  String get someWordsAreStillUntimedFinish =>
      'У некоторых слов ещё нет тайминга. Завершите разметку в режиме синхронизации по словам.';

  @override
  String get somethingWentWrong => 'Что-то пошло не так';

  @override
  String song2(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count песен',
      many: '$count песен',
      few: '$count песни',
      one: '$count песня',
    );
    return '$_temp0';
  }

  @override
  String song3(int count, Object server) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count песен',
      many: '$count песен',
      few: '$count песни',
      one: '$count песня',
    );
    return '$_temp0 · $server';
  }

  @override
  String get songActions => 'Действия с песней';

  @override
  String get songArtist => 'Исполнитель песни';

  @override
  String get songCount => 'Количество песен';

  @override
  String get songGestures => 'Жесты для песен';

  @override
  String get songMetadata => 'Метаданные песни';

  @override
  String get songTitle => 'Название песни';

  @override
  String songUnit(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'песен',
      many: 'песен',
      few: 'песни',
      one: 'песня',
    );
    return '$_temp0';
  }

  @override
  String songs(Object arg1, Object arg2) {
    return '$arg1 • песен: $arg2';
  }

  @override
  String songs12(Object arg1) {
    return 'Песен: $arg1';
  }

  @override
  String songs13(Object count) {
    return 'Песен: $count';
  }

  @override
  String get songs14 => 'Песни';

  @override
  String songs15(Object arg1) {
    return 'Песен: $arg1';
  }

  @override
  String songs2(Object songCount) {
    return 'Песен: $songCount';
  }

  @override
  String songs3(Object arg1) {
    return 'Песен: $arg1';
  }

  @override
  String songs4(Object _totalSongs) {
    return 'Песен: $_totalSongs';
  }

  @override
  String songs5(Object arg1) {
    return 'Песен: $arg1';
  }

  @override
  String songs9(Object arg1) {
    return 'Песен: $arg1';
  }

  @override
  String songsAlbums(Object arg1, Object uniqueAlbums) {
    return 'Песен: $arg1 • Альбомов: $uniqueAlbums';
  }

  @override
  String songsAlbums2(Object arg1, Object albumCount) {
    return 'Песен: $arg1 · Альбомов: $albumCount';
  }

  @override
  String get songsCategories => 'Песни и категории';

  @override
  String songsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count песен',
      many: '$count песен',
      few: '$count песни',
      one: '$count песня',
    );
    return '$_temp0';
  }

  @override
  String songsFound(Object arg1) {
    return 'Найдено песен: $arg1';
  }

  @override
  String songsIn(int songs, int folders) {
    String _temp0 = intl.Intl.pluralLogic(
      songs,
      locale: localeName,
      other: '$songs песен',
      many: '$songs песен',
      few: '$songs песни',
      one: '$songs песня',
    );
    String _temp1 = intl.Intl.pluralLogic(
      folders,
      locale: localeName,
      other: '$folders папках',
      many: '$folders папках',
      few: '$folders папках',
      one: '$folders папке',
    );
    return '$_temp0 в $_temp1';
  }

  @override
  String songsInRotation(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count песен в вашей ротации',
      many: '$count песен в вашей ротации',
      few: '$count песни в вашей ротации',
      one: '$count песня в вашей ротации',
    );
    return '$_temp0';
  }

  @override
  String get songsTab => 'Вкладка «Песни»';

  @override
  String songsU2022Albums(Object arg1, Object uniqueAlbums) {
    return 'Песен: $arg1 • Альбомов: $uniqueAlbums';
  }

  @override
  String get songsYouPlayWillAppearHere => 'Здесь появятся прослушанные песни';

  @override
  String get songsYouScanIntoYourLibrary =>
      'Здесь появятся песни, добавленные при сканировании медиатеки';

  @override
  String get sortBy => 'СОРТИРОВКА';

  @override
  String get sortFilter => 'Сортировка и фильтры';

  @override
  String get sortSongs => 'Сортировать песни';

  @override
  String get source => 'Источник';

  @override
  String get sourceRate => 'Частота источника';

  @override
  String get spaceBetweenTheTwoBars => 'Расстояние между двумя полосами';

  @override
  String get spaceOdyssey => 'Космическая одиссея';

  @override
  String get spatialTime => 'Пространство и время';

  @override
  String get speedUp => 'Ускорить';

  @override
  String get springPhysicsEnergeticAndReactive =>
      'Пружинная физика — энергичная и отзывчивая';

  @override
  String get stampNext => 'Метка и далее';

  @override
  String get stampNow => 'Поставить метку';

  @override
  String get stampThisLineFirstToEdit =>
      'Сначала поставьте временную метку для этой строки, чтобы редактировать тайминг слов.';

  @override
  String get standard => 'Стандартный';

  @override
  String get standardBluetoothRoutingViaAndroid =>
      'Стандартная маршрутизация Bluetooth через Android';

  @override
  String get standardEngine => 'Стандартный движок';

  @override
  String get starlightSerenade => 'Звёздная серенада';

  @override
  String get start => 'Начать';

  @override
  String get startAtNow => 'Начать с текущего момента';

  @override
  String get startBuildingYourHome => 'Настройте главный экран';

  @override
  String get startPlayingToPopulateThisSpace =>
      'Включите музыку, чтобы заполнить этот раздел';

  @override
  String get startStreaming => 'Начать трансляцию';

  @override
  String get startedPresetDownload => 'Загрузка пресета начата.';

  @override
  String get state => 'Состояние';

  @override
  String get status => 'Статус';

  @override
  String get stereo => 'Стерео';

  @override
  String get stop => 'Остановить';

  @override
  String get stopCasting => 'Остановить трансляцию';

  @override
  String get stopStreaming => 'Остановить трансляцию';

  @override
  String get stopUsbOnQuit => 'Останавливать USB при выходе';

  @override
  String stoppingIn(Object arg1) {
    return 'Остановка через $arg1';
  }

  @override
  String get storeOn => 'Сохранить на';

  @override
  String get storedAsASaltedHashNever =>
      'Хранится в виде хэша с солью, никогда не в открытом виде';

  @override
  String get storedEncodedPlaybackUnavailableInThis =>
      'Хранится в кодировке base64 — необходимо для входа по NTLM';

  @override
  String get stormChasers => 'Охотники за бурей';

  @override
  String get strategy => 'Стратегия';

  @override
  String get stream => 'Поток';

  @override
  String get streamConfigurationNotAvailable =>
      'Конфигурация потока недоступна';

  @override
  String get streamStable => 'Поток стабилен';

  @override
  String get streaming => 'Трансляция';

  @override
  String get streamingFromQueue => 'Трансляция из очереди';

  @override
  String get strong => 'Сильная';

  @override
  String get studioGradeOutputForExternalDacs =>
      'Вывод студийного класса для внешних ЦАП и усилителей для наушников. Обходит аудиообработку Android ради чистого звучания.';

  @override
  String get sub => 'Саб';

  @override
  String subfolderCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count подпапок',
      many: '$count подпапок',
      few: '$count подпапки',
      one: '$count подпапка',
    );
    return '$_temp0';
  }

  @override
  String get subsonic => 'Subsonic';

  @override
  String get subtle => 'Лёгкая';

  @override
  String get supportFlick => 'Поддержать Flick';

  @override
  String get supportFlickOnKoFi => 'Поддержать Flick на Ko-fi';

  @override
  String get surfaceShading => 'Затенение поверхности';

  @override
  String get swipeHorizontallyToFineTuneEach =>
      'Проведите по горизонтали, чтобы точно настроить каждую центральную полосу.';

  @override
  String get swipeLeftRightToSkipTracks =>
      'Свайп влево/вправо для переключения треков';

  @override
  String get swipeToShowOrHideThe =>
      'Проведите, чтобы показать или скрыть визуализатор';

  @override
  String get switchSongs => 'Переключать песни';

  @override
  String get switchToTheExclusiveUsbPath =>
      'Автоматически переключаться на эксклюзивный USB-тракт при подключении ЦАП. Отклонённые ЦАП запоминаются.';

  @override
  String get switchedBackToTheAutomaticLyrics =>
      'Выбран автоматический источник текстов песен.';

  @override
  String get syllablesTapALetterToSplit =>
      'Слоги — нажмите на букву, чтобы разделить или объединить:';

  @override
  String get symmetricalBarsMirroredFromTheCenter =>
      'Симметричные полосы, отражённые от центра';

  @override
  String syncFailed(Object e) {
    return 'Ошибка синхронизации: $e';
  }

  @override
  String get syncNow => 'Синхронизировать';

  @override
  String get syncServerPlaylists => 'Синхронизировать плейлисты сервера';

  @override
  String get synced => 'Синхронизировано';

  @override
  String synced2(Object arg1) {
    return 'Синхронизировано $arg1';
  }

  @override
  String get syncedLrc => 'Синхронизированный LRC';

  @override
  String syncedPlaylistFromServers(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count плейлистов',
      many: '$count плейлистов',
      few: '$count плейлиста',
      one: '$count плейлист',
    );
    return 'Синхронизировано с серверов: $_temp0';
  }

  @override
  String get syncing => 'Синхронизация…';

  @override
  String get synthwaveCity => 'Синтвейв-сити';

  @override
  String get systemAndroidMixer => 'Системная (микшер Android)';

  @override
  String get tagsWereWrittenButCouldNot =>
      'Теги записаны, но не удалось подтвердить запись повторным чтением файла. Повторное сканирование медиатеки устранит расхождения.';

  @override
  String tap(Object label) {
    return 'Нажатие: «$label»';
  }

  @override
  String get tapABandToExpandDrag =>
      'Нажмите на полосу, чтобы раскрыть её. Потяните ручку для настройки. Нажмите на значение для ввода вручную.';

  @override
  String get tapAllOrEnableAChip =>
      'Нажмите «Все» или включите фильтр, чтобы увидеть результаты';

  @override
  String get tapChipsToFilterCategories =>
      'Нажимайте на метки, чтобы фильтровать категории';

  @override
  String get tapEditTextTopRight =>
      '1. Нажмите «Изменить текст» (справа вверху) и вставьте текст — по одной строке на ряд.\n2. Запустите воспроизведение песни.\n3. Выберите текущую строку в списке строк.\n4. Нажмите «Метка и далее», когда услышите эту строку.\n5. Сохраните результат.';

  @override
  String get tapIconsToSwitchTabsLong =>
      'Нажимайте на значки для переключения вкладок. Удерживайте, чтобы настроить панель.';

  @override
  String get tapTheHeartIconOnAny =>
      'Нажмите на значок сердца у любой песни,\nчтобы добавить её в избранное';

  @override
  String get tapTheMiniPlayerForWaveform =>
      'Нажмите на мини-плеер, чтобы открыть волновую шкалу, эквалайзер, текст и визуализатор.';

  @override
  String get tapToInspect12602280Png =>
      'Нажмите для просмотра · 1260 × 2280 PNG';

  @override
  String get tapToPlayLongPressFor =>
      'Нажмите для воспроизведения, удерживайте для меню (очередь, играть далее, инфо).';

  @override
  String get tapToPreview => 'Нажмите для предпросмотра';

  @override
  String targetMs(Object arg1) {
    return 'цель $arg1 мс';
  }

  @override
  String get tempo => 'Темп';

  @override
  String tempoX(Object arg1) {
    return 'Темп ${arg1}x';
  }

  @override
  String test(Object arg1) {
    return 'Тест: $arg1';
  }

  @override
  String get testConnection => 'Проверить подключение';

  @override
  String get textGestures => 'Текст и жесты';

  @override
  String get textPlacement => 'Расположение текста';

  @override
  String get textPlacement2 => 'Расположение текста';

  @override
  String get textSize => 'Размер текста';

  @override
  String get textSize2 => 'Размер текста';

  @override
  String get thatSTheTour => 'Вот и весь обзор!';

  @override
  String get theAudioEngineDeterminesHowYour =>
      'Аудиодвижок определяет, как воспроизводится ваша музыка. Каждый вариант по-своему сочетает надёжность, качество и совместимость.';

  @override
  String get theIsochronousUsbEngineWillBe =>
      'Изохронный USB-движок будет останавливаться при выходе из приложения.';

  @override
  String get theIsochronousUsbEngineWillStay =>
      'Изохронный USB-движок продолжит работать после выхода из приложения.';

  @override
  String get theNamesShowingUpAgainAnd =>
      'Имена, которые снова и снова появляются в вашей недавней очереди.';

  @override
  String get thePosterIsNotReadyYet =>
      'Постер ещё не готов. Попробуйте сохранить снова.';

  @override
  String get theTracksDominatingYourWeeklyAnd =>
      'Треки, лидирующие в ваших еженедельных и ежемесячных итогах.';

  @override
  String get thisAppIsBuiltByA =>
      'Это приложение создано одним разработчиком без бюджета. Если вам нравится звук высокого качества, поддержите разработку на Ko-fi.';

  @override
  String get thisDevice => 'Это устройство';

  @override
  String get thisFolderAppearsToBeEmpty => 'Похоже, эта папка пуста';

  @override
  String get thisMonth => 'Этот месяц';

  @override
  String get thisMonthSRecap => 'Итоги месяца';

  @override
  String thisRemovesAllEntriesFromMemory(Object arg1) {
    return 'Из памяти будут удалены все записи ($arg1).';
  }

  @override
  String get thisSlowsPlaybackTo432440 =>
      'Замедляет воспроизведение в соотношении 432/440 (высота тона и темп ниже примерно на 1,8%) и отключает bit-perfect вывод. Музыка будет звучать чуть ниже. Включайте только если осознанно хотите строй A=432 Гц.';

  @override
  String get thisSongHasNoFilePath =>
      'У этой песни нет пути к файлу, её нельзя редактировать.';

  @override
  String get thisSongIsMissingAlbumMetadata =>
      'У этой песни отсутствуют метаданные альбома, поэтому онлайн-поиск ограничен.';

  @override
  String get thisSongOnly => 'Только эта песня';

  @override
  String get thisWeek => 'Эта неделя';

  @override
  String get thisWeekSRecap => 'Итоги недели';

  @override
  String get thisYearSRecap => 'Итоги года';

  @override
  String get threshold => 'Порог';

  @override
  String get thunderRoad => 'Грозовая дорога';

  @override
  String get tidal => 'Tidal';

  @override
  String get timeShift => 'Сдвиг времени';

  @override
  String get timestamp => 'Временная метка';

  @override
  String get tips => 'Советы';

  @override
  String get title => 'Название';

  @override
  String get toRemove => 'К удалению';

  @override
  String get today => 'Сегодня';

  @override
  String get todaySRecap => 'Итоги дня';

  @override
  String get toneControls => 'Регулировка тембра';

  @override
  String get tools => 'Инструменты';

  @override
  String get top => 'Сверху';

  @override
  String get topAlbum => 'Главный альбом';

  @override
  String get topArtist => 'Главный исполнитель';

  @override
  String get topArtists => 'Топ исполнителей';

  @override
  String get topSongs => 'Топ песен';

  @override
  String get topSongs2 => 'Топ песен';

  @override
  String get track => 'Трек';

  @override
  String track2(Object arg1) {
    return 'Трек $arg1';
  }

  @override
  String get track3 => 'Трек №';

  @override
  String get trackBitDepth => 'Разрядность трека';

  @override
  String get trackChannels => 'Каналы трека';

  @override
  String get trackCount => 'Количество треков';

  @override
  String get trackDsdRate => 'Частота DSD трека';

  @override
  String get trackNumber => 'Номер трека';

  @override
  String get trackSampleRate => 'Частота дискретизации трека';

  @override
  String get trackTime => 'Длительность треков';

  @override
  String get trackTimeSumsTheFullDuration =>
      'Длительность треков суммирует полную продолжительность записанных прослушиваний.';

  @override
  String tracks(Object _totalTracks) {
    return 'Треков: $_totalTracks';
  }

  @override
  String tracks2(Object arg1) {
    return 'Треков: $arg1';
  }

  @override
  String tracks3(Object arg1) {
    return 'Треков: $arg1';
  }

  @override
  String tracks4(Object arg1) {
    return 'Треков: $arg1';
  }

  @override
  String tracks5(Object arg1, Object arg2) {
    return '$arg1 · треков: $arg2';
  }

  @override
  String tracks6(Object arg1) {
    return 'Треков: $arg1';
  }

  @override
  String tracks7(Object trackCount, Object arg1) {
    return 'Треков: $trackCount • $arg1';
  }

  @override
  String tracks8(Object arg1) {
    return 'Треков: $arg1';
  }

  @override
  String tracksLikedSongsPlaylists(
    Object songCount,
    Object favoriteCount,
    Object playlistCount,
  ) {
    return 'Треков: $songCount, любимых песен: $favoriteCount, плейлистов: $playlistCount';
  }

  @override
  String tracksReadyToRevisit(Object favoritesCount) {
    return 'Треков, к которым стоит вернуться: $favoritesCount';
  }

  @override
  String get tracksThatFitTheQuieterSide =>
      'Треки для более спокойных моментов прослушивания.';

  @override
  String get transparent => 'Прозрачный';

  @override
  String get treble => 'Верхние частоты';

  @override
  String get trueRandomMayRepeatBeforeList =>
      'Истинно случайный (может повторяться до конца списка)';

  @override
  String get truncate => 'Обрезать';

  @override
  String get tryAdjustingYourSearchQuery =>
      'Попробуйте изменить поисковый запрос';

  @override
  String get tryAgain => 'Повторить';

  @override
  String get tryAnotherKeywordOrEnableMore =>
      'Попробуйте другой запрос или включите больше категорий';

  @override
  String get tryOriginalSearch => 'Повторить исходный поиск';

  @override
  String get tryPickingALocalImageIf =>
      'Попробуйте выбрать локальное изображение, если метаданные релиза нестандартные.';

  @override
  String get typeABrandAndModelTo =>
      'Введите бренд и модель для поиска в сети.';

  @override
  String get u162ByteSubslotsLlRr => 'U16 — 2-байтовые подслоты, LL|RR';

  @override
  String u2022(Object arg1, Object valueLabel) {
    return '$arg1  •  $valueLabel';
  }

  @override
  String u20223(Object arg1, Object gainLabel) {
    return '$arg1  •  $gainLabel';
  }

  @override
  String u2022Bit(Object arg1) {
    return ' • $arg1 бит';
  }

  @override
  String get u324ByteSubslotsLlllRrrr =>
      'U32 — 4-байтовые подслоты, LLLL|RRRR (устаревший)';

  @override
  String get u8ByteInterleavedLrlr => 'U8 — побайтовое чередование LRLR';

  @override
  String get u8ByteInterleavedRecommendedDefault =>
      'U8 — побайтовое чередование, рекомендуется по умолчанию';

  @override
  String get uac2IsNotAvailableOnThis => 'UAC2 недоступен на этой платформе';

  @override
  String get uac2NotAvailableOnThisPlatform =>
      'UAC2 недоступен на этой платформе';

  @override
  String get uac2Preferences => 'Настройки UAC2';

  @override
  String get uac2PreferencesResetSuccessfully =>
      'Настройки UAC2 успешно сброшены';

  @override
  String get unableToCheckForUpdatesRight =>
      'Не удалось проверить обновления прямо сейчас.';

  @override
  String unavailable(Object featureName) {
    return 'Функция «$featureName» недоступна';
  }

  @override
  String get unavailable2 => 'Недоступно';

  @override
  String underruns(Object arg1) {
    return 'Опустошений буфера: $arg1';
  }

  @override
  String get undo => 'Отменить';

  @override
  String get unfavorite => 'Убрать из избранного';

  @override
  String get unfavoriteSelected => 'Убрать выбранные из избранного';

  @override
  String get uniqueArtists => 'Уникальных исполнителей';

  @override
  String get universalCompatibility => 'Универсальная совместимость';

  @override
  String get unknown => 'Неизвестно';

  @override
  String get unknownAlbum => 'Неизвестный альбом';

  @override
  String get unknownArtist => 'Неизвестный исполнитель';

  @override
  String get unknownBitrate => 'Неизвестный битрейт';

  @override
  String get unknownFolder => 'Неизвестная папка';

  @override
  String get unknownTitle => 'Без названия';

  @override
  String get unknownTrack => 'Неизвестный трек';

  @override
  String unlocked(Object unlocked, Object arg1) {
    return 'Открыто $unlocked из $arg1';
  }

  @override
  String get unmute => 'Включить звук';

  @override
  String get unreported => 'Нет данных';

  @override
  String get unsavedChanges => 'Несохранённые изменения';

  @override
  String up(Object arg1) {
    return '$arg1 вверх';
  }

  @override
  String get upNext => 'Далее';

  @override
  String upcomingSong(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count следующих песен',
      many: '$count следующих песен',
      few: '$count следующие песни',
      one: '$count следующая песня',
    );
    return '$_temp0';
  }

  @override
  String get update => 'Обновить';

  @override
  String get updateAvailable => 'Доступно обновление';

  @override
  String get updateNoticeHidden => 'Уведомление об обновлении скрыто.';

  @override
  String updated(Object arg1) {
    return 'Обновлено $arg1';
  }

  @override
  String updatedAlbumArtFor(Object arg1) {
    return 'Обложка альбома «$arg1» обновлена.';
  }

  @override
  String updatedAlbumArtFor2(Object arg1) {
    return 'Обложка альбома «$arg1» обновлена.';
  }

  @override
  String get upload => 'Загрузить';

  @override
  String uploadFailed(Object arg1) {
    return 'Ошибка загрузки ($arg1).';
  }

  @override
  String uploadFailed2(Object e) {
    return 'Ошибка загрузки: $e';
  }

  @override
  String get uploadLogsAsALink => 'Загрузить журнал и получить ссылку?';

  @override
  String get upnpDlna => 'UPnP / DLNA';

  @override
  String get urbPacket => 'Пакет URB';

  @override
  String get urbTransfer => 'Передача URB';

  @override
  String get urbanEchoes => 'Городское эхо';

  @override
  String get usbAudioDevice => 'USB-аудиоустройство';

  @override
  String get usbAudioDevices => 'USB-аудиоустройства';

  @override
  String get usbAudioError => 'Ошибка USB-аудио';

  @override
  String get usbDacAutoBitPerfectOffers =>
      'Предложения авто-включения bit-perfect для USB DAC сброшены.';

  @override
  String get usbNotConnected => 'USB не подключён';

  @override
  String get usbRouteVolume => 'Громкость USB-тракта';

  @override
  String get usbVolume => 'Громкость USB';

  @override
  String get useAFixed48khz16bitOutput =>
      'Использовать фиксированный вывод 48 кГц / 16 бит для лучшей совместимости';

  @override
  String get useAaudioDirectlyLowestLatencyOn =>
      'Использовать AAudio напрямую. Минимальная задержка на Android 8.1 и новее.';

  @override
  String get useAlbumArtAsBackground => 'Использовать обложку альбома как фон';

  @override
  String get useAutoSource => 'Автовыбор источника';

  @override
  String get useCurrentTime => 'Текущее время';

  @override
  String get useExistingFile => 'Выбрать файл';

  @override
  String get useExistingFileInTheLyrics =>
      '- «Выбрать файл» на панели текстов привязывает файл `.lrc`, `.txt` или `.xml`.\n- Если у части строк нет меток, Lokal заполнит их автоматически.\n- При сохранении файл записывается рядом с песней, если это возможно; иначе Lokal сохраняет привязанную копию.';

  @override
  String get useMmSsCcEG => 'Формат мм:сс.сс, например 01:23.45';

  @override
  String get useTheDefaultMonochromeTheme =>
      'Использовать стандартную монохромную тему.';

  @override
  String get useTheHighestFixedOutputRate =>
      'Использовать максимальную доступную фиксированную частоту и разрядность вывода';

  @override
  String get useTheLegacyOpenslEsBackend =>
      'Использовать устаревший бэкенд OpenSL ES. Резервный вариант для старых или проблемных устройств.';

  @override
  String get useTheVerifiedDirectUsbPath =>
      'Использовать проверенный прямой USB-тракт и отключить программный DSP, нарушающий bit-perfect воспроизведение на внешнем USB DAC.';

  @override
  String get userToken => 'Токен пользователя';

  @override
  String get username => 'Имя пользователя';

  @override
  String get variableBitrateLowLatency => 'Переменный битрейт, низкая задержка';

  @override
  String get variousArtists2 => 'Разные исполнители';

  @override
  String get velvetNoir => 'Бархатный нуар';

  @override
  String get vendorId => 'ID производителя';

  @override
  String get verboseDartRustAndCrashLogs =>
      'Подробные журналы Dart, Rust и сбоев';

  @override
  String get verified => 'Проверено';

  @override
  String version2(Object arg1) {
    return 'Версия $arg1';
  }

  @override
  String get verticalBarsClassicSpectrumAnalyzer =>
      'Вертикальные полосы — классический анализатор спектра';

  @override
  String get verticalBarsThatAnimateAcrossThe =>
      'Вертикальные полосы, анимированные по всей ширине экрана.';

  @override
  String get vibrant => 'Насыщенный';

  @override
  String get viewAsGrid => 'Показать сеткой';

  @override
  String get viewAsList => 'Показать списком';

  @override
  String get viewMetadata => 'Показать метаданные';

  @override
  String get viewQueue => 'Показать очередь';

  @override
  String get visualizer => 'Визуализатор';

  @override
  String get visualizerAlbumColorsDescription =>
      'Повторять цвета обложки альбома; монохром, если обложка недоступна';

  @override
  String get visualizerBlocks => 'Затухающие блоки';

  @override
  String get visualizerBlocksDescription =>
      'Сегментированные полосы с мягко затухающим шлейфом';

  @override
  String get visualizerColors => 'Цвета';

  @override
  String get visualizerMonochrome => 'Монохром';

  @override
  String get visualizerMonochromeDescription =>
      'Белый и серый, независимо от обложки альбома';

  @override
  String get visualizerRainbow => 'Радуга';

  @override
  String get visualizerRainbowDescription =>
      'Спектр цветов по всему визуализатору';

  @override
  String get volume => 'Громкость';

  @override
  String get volumeControl => 'Управление громкостью';

  @override
  String get volumeIsFixedWhileBitPerfect =>
      'Громкость зафиксирована, пока активен bit-perfect вывод и у этого ЦАП нет аппаратного регулятора громкости.';

  @override
  String get volumeIsFixedWhileBitPerfect2 =>
      'Громкость зафиксирована при активном bit-perfect выводе: поток передаётся без изменений, а у этого ЦАП нет аппаратного регулятора громкости.';

  @override
  String wAgo(Object arg1) {
    return '$arg1 нед. назад';
  }

  @override
  String get waitingForBrowserAuthorization =>
      'Ожидание авторизации в браузере…';

  @override
  String get waitingForPlayback => 'Ожидание воспроизведения';

  @override
  String get wantEveryControlDocumentedOpenThe =>
      'Нужна справка по каждому элементу? Откройте встроенное руководство в любой момент: Настройки → Справка и руководство.';

  @override
  String was(Object arg1) {
    return 'было: $arg1';
  }

  @override
  String get wave => 'Волна';

  @override
  String get waveform => 'Форма волны';

  @override
  String weLlKeepTheBestQuality(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count копий',
      many: '$count копий',
      few: '$count копии',
      one: '$count копию',
    );
    return 'Мы сохраним версию лучшего качества в каждой группе (в приоритете наличие обложки, затем самый высокий битрейт) и удалим $_temp0. Файлы на диске не удаляются.';
  }

  @override
  String weLlKeepYourCheckedVersion(int kept, int removed) {
    String _temp0 = intl.Intl.pluralLogic(
      kept,
      locale: localeName,
      other: '$kept выбранных версий',
      many: '$kept выбранных версий',
      few: '$kept выбранные версии',
      one: '$kept выбранную версию',
    );
    String _temp1 = intl.Intl.pluralLogic(
      removed,
      locale: localeName,
      other: '$removed лишних копий',
      many: '$removed лишних копий',
      few: '$removed лишние копии',
      one: '$removed лишнюю копию',
    );
    return 'Мы сохраним $_temp0 и удалим $_temp1 из вашей медиатеки. Аудиофайлы на диске не удаляются.';
  }

  @override
  String get webdav => 'WebDAV';

  @override
  String get weekly => 'Еженедельно';

  @override
  String get welcomeBackLetSStartA =>
      'С возвращением — начнём серию прослушиваний.';

  @override
  String get welcomeToFlick => 'Добро пожаловать в Lokal!';

  @override
  String get welcomeToFlick2 => 'Добро пожаловать в Lokal';

  @override
  String get whatSNew => 'Что нового';

  @override
  String get whenYouPlayOverBluetoothAndroid =>
      'При воспроизведении по Bluetooth кодек согласуется между Android и вашими наушниками или колонкой.';

  @override
  String get whereShouldTheLrcFileBe => 'Куда сохранить файл .lrc?';

  @override
  String get whisperWorld => 'Мир шёпота';

  @override
  String get whisperedSecrets => 'Шёпот тайн';

  @override
  String get white => 'Белый';

  @override
  String get wholeAlbum => 'Весь альбом';

  @override
  String wide(Object amount) {
    return '$amount% (широко)';
  }

  @override
  String get widgets => 'Виджеты';

  @override
  String get width => 'Ширина';

  @override
  String get wildWeather => 'Буйная стихия';

  @override
  String get willBeRemoved => 'Будет удалено';

  @override
  String get willKeep => 'Будет сохранено';

  @override
  String get wiredOutput => 'Проводной выход';

  @override
  String word(Object arg1, Object arg2) {
    return 'Слово $arg1 · «$arg2»';
  }

  @override
  String word2(Object arg1, Object token) {
    return 'Слово $arg1 · «$token»';
  }

  @override
  String get wordSync => 'Синхронизация по словам';

  @override
  String get wordSyncModeKaraoke => 'Режим синхронизации по словам (караоке)';

  @override
  String wordTimelineLine(Object arg1) {
    return 'Таймлайн слов · Строка $arg1';
  }

  @override
  String get writeADescription => 'Напишите описание';

  @override
  String x(Object min) {
    return '${min}x';
  }

  @override
  String x2(Object max) {
    return '${max}x';
  }

  @override
  String x3(Object currentSpeed) {
    return '${currentSpeed}x';
  }

  @override
  String yAgo(Object arg1) {
    return '$arg1 г. назад';
  }

  @override
  String get year => 'Год';

  @override
  String get yearly => 'Ежегодно';

  @override
  String get yesterday => 'Вчера';

  @override
  String get youCanAlsoChangeTheCodec =>
      'Вы также можете сменить кодек в параметрах разработчика Android в разделе «Аудиокодек Bluetooth».';

  @override
  String get youCustomizedWhichVersionsToKeep =>
      'Вы сами выбрали, какие версии сохранить. Отлично — всё под контролем.';

  @override
  String get youHaveUnsavedChangesAreYou =>
      'У вас есть несохранённые изменения. Вы уверены, что хотите их отменить?';

  @override
  String get youHaveUnsavedLyricEditsLeave =>
      'У вас есть несохранённые правки текста. Выйти из студии синхронизации без сохранения?';

  @override
  String get youReOffline => 'Вы не в сети';

  @override
  String get youReOfflineSomeOnlineFeatures =>
      'Вы не в сети. Некоторые онлайн-функции могут не работать.';

  @override
  String get youVeHitTheThresholdKeep => 'Порог достигнут — так держать!';

  @override
  String get yourCollectionAtAGlance => 'Обзор вашей коллекции';

  @override
  String get yourCustomCollections => 'Ваши пользовательские подборки';

  @override
  String get yourHeaviestRotationRightNow =>
      'В самой активной ротации прямо сейчас';

  @override
  String get yourLatestLibraryScans => 'Последние сканирования медиатеки';

  @override
  String get yourLibrary => 'Ваша медиатека';

  @override
  String get yourLibraryAtAGlance => 'Обзор вашей медиатеки';

  @override
  String get yourLibraryIsTidyWeLl =>
      'В медиатеке порядок. Мы сообщим, если после следующего сканирования появятся новые дубликаты.';

  @override
  String get yourListeningHistoryIsStillYours =>
      'Ваша история прослушиваний на месте. Попробуйте загрузить её снова.';

  @override
  String get yourListensWillRemainOnListenbrainz =>
      'Ваши прослушивания останутся на ListenBrainz, но Lokal перестанет их отправлять.';

  @override
  String get yourLogsAreUploadedToDpaste =>
      'Журналы загружаются на dpaste.com по скрытой ссылке со сроком действия 30 дней. Любой, у кого есть ссылка, сможет их прочитать — журналы могут содержать пути к файлам и сведения об устройстве.';

  @override
  String get yourMonthlyRecapNeedsABit =>
      'Для ежемесячных итогов нужно немного больше времени прослушивания в этом месяце.';

  @override
  String get yourMostReplayedTrack => 'Ваш самый часто повторяемый трек';

  @override
  String get yourMusicIsBeingScrobbled => 'Ваша музыка скробблится';

  @override
  String get yourMusicIsBeingSubmitted => 'Ваши прослушивания отправляются';

  @override
  String get yourMusicOnRepeat => 'Ваша музыка. На повторе.';

  @override
  String get yourNewAudioEngineIsReady =>
      'Новый аудиодвижок готов. Перезапустите Lokal, чтобы применить изменения.';

  @override
  String get yourNextFavoriteIsWaiting =>
      'Ваш следующий любимый трек уже ждёт.';

  @override
  String get yourNextFavoriteNisWaiting =>
      'Ваш следующий любимый трек\nуже ждёт.';

  @override
  String get yourPlaylists => 'Ваши плейлисты';

  @override
  String get yourScrobblingHistoryWillRemainOn =>
      'Ваша история скробблинга останется на Last.fm, но Lokal перестанет отправлять скробблы.';

  @override
  String get yourSessionHistory => 'История вашей сессии';

  @override
  String get yourWeeklyRecapAppearsOnceYou =>
      'Еженедельные итоги появятся, как только вы начнёте слушать музыку на этой неделе.';

  @override
  String get yourWholeLibraryLivesHereTap =>
      'Здесь собрана вся ваша медиатека. Нажмите на любую песню, чтобы включить её.';

  @override
  String get yourYearlyRecapFillsInAs =>
      'Годовые итоги наполняются по мере того, как вы слушаете музыку в течение года.';

  @override
  String get linkDesktop => 'Связь с ПК';

  @override
  String get linkDevices => 'Устройства';

  @override
  String get linkConnectDesktop => 'Подключите Lokal на ПК';

  @override
  String get linkPairingHint =>
      'На компьютере откройте «Пульт с телефона» и выберите «Привязать телефон». Оба устройства должны быть в одной сети Wi-Fi.';

  @override
  String get linkScanQr => 'Сканировать QR-код привязки';

  @override
  String get linkInvalidQr => 'Это некорректный код привязки Lokal.';

  @override
  String get linkCameraUnavailable =>
      'Доступ к камере недоступен. Вернитесь назад и введите адрес ПК и код привязки вручную.';

  @override
  String get linkSearchDesktops => 'Найти ПК в сети Wi-Fi';

  @override
  String get linkSearching => 'Поиск компьютеров…';

  @override
  String get linkNoDesktopFound =>
      'Компьютер не найден. Вы можете ввести его адрес вручную.';

  @override
  String get linkDesktopAddress => 'Адрес компьютера';

  @override
  String get linkPairingCode => 'Шестизначный код привязки';

  @override
  String get linkPair => 'Привязать ПК';

  @override
  String get linkConnecting => 'Подключение…';

  @override
  String get linkMatchTheme => 'Повторять тему и акцент ПК';

  @override
  String get linkConnected => 'Подключено';

  @override
  String get linkOffline => 'Не в сети';

  @override
  String get linkReconnect => 'Переподключить';

  @override
  String get linkDisconnect => 'Отключить';

  @override
  String get linkForget => 'Забыть компьютер';

  @override
  String get linkForgetDescription =>
      'Удалить сохранённые учётные данные этого ПК с телефона? Ваша музыка и объединённая медиатека останутся на телефоне.';

  @override
  String get linkActionFailed =>
      'Не удалось выполнить действие через связь с ПК.';

  @override
  String get linkPlayback => 'Устройство вывода';

  @override
  String get linkControlDesktop => 'Управлять ПК с экрана «Сейчас играет»';

  @override
  String get linkPlayOnDesktop => 'Воспроизвести на ПК';

  @override
  String get linkPlayOnPhone => 'Воспроизвести на этом телефоне';

  @override
  String get linkUpdateDesktop =>
      'Обновите Lokal на ПК, чтобы управлять этим телефоном с компьютера и синхронизировать медиатеку.';

  @override
  String get linkMergeLibraries => 'Объединить медиатеки';

  @override
  String get linkMergePreview =>
      'Сохраните музыку, лайки и плейлисты с обоих устройств. Завершённые прослушивания объединяются один раз. Музыкальные файлы не удаляются. Дальнейшие изменения синхронизируются в обе стороны.';

  @override
  String get linkMerge => 'Объединить';

  @override
  String get linkNotNow => 'Не сейчас';

  @override
  String linkHistoryCount(int count) {
    return 'Прослушиваний с ПК готово к объединению: $count';
  }

  @override
  String get linkSendDownloads => 'Отправлять загрузки с телефона на ПК';

  @override
  String get linkSendDownloadsDescription =>
      'Копировать новые загрузки телефона и недостающие переданные песни на привязанный ПК. Исходные файлы останутся на телефоне.';

  @override
  String get linkLegacyRemote => 'Подключиться к старой версии ПК вручную';

  @override
  String get linkDownloadToPhone => 'Скачать на телефон';

  @override
  String get linkDownloaded => 'Сохранено на этом телефоне';

  @override
  String linkOutputName(String name) {
    return 'Lokal на $name';
  }

  @override
  String get linkOnboardingDescription =>
      'Управляйте любым устройством, переносите очередь между ними и храните лайки, плейлисты и историю прослушиваний вместе. Это необязательно и можно настроить позже.';

  @override
  String get linkFollowAccent => 'Повторять акцент приложения';

  @override
  String get linkPerformanceTitle => 'Сделать анимации плавнее?';

  @override
  String get linkPerformanceBody =>
      'Режим производительности сохраняет вашу тему, но использует сплошные поверхности вместо эффекта стекла.';

  @override
  String get linkEnablePerformance => 'Включить режим производительности';
}
