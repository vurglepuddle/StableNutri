import 'package:http/http.dart' as http;
import 'package:logging/logging.dart';
import 'package:opennutritracker/core/utils/app_const.dart';
import 'package:opennutritracker/core/utils/ont_http_client.dart';

/// One name that barcode-list.ru's users have given a code, with how many of
/// them chose it.
class BarcodeListName {
  final String name;
  final String unit;
  final int rating;

  const BarcodeListName(this.name, this.unit, this.rating);
}

/// What barcode-list.ru knows about one code: the name its users settled on,
/// and every variant behind it.
class BarcodeListResult {
  final String barcode;

  /// The top-voted name as the site prints it in its page title — ordinary
  /// capitalisation, unlike the shouty cash-register spelling of the rows.
  final String bestName;

  /// All variants, most voted first. They often carry what the best name
  /// leaves out (the maker, the fat percentage), which a later lookup by
  /// name can use.
  final List<BarcodeListName> variants;

  const BarcodeListResult(this.barcode, this.bestName, this.variants);
}

/// Resolves a barcode to a product name through barcode-list.ru, a Russian
/// barcode register fed by shop back-office software. It has no nutrition,
/// only names — but for Russian products Open Food Facts has never seen, a
/// name is the part that is otherwise hardest to come by.
///
/// There is no API: the lookup is the site's own search page, parsed. Its
/// robots.txt allows crawling with a 10 s delay; one request per unknown
/// scan stays far inside that. The site turns away Dart's default user
/// agent with a 403, so requests go out under the app's own.
class BarcodeListDataSource {
  /// Key in [ConfigEntity.foodSourceToggles]; absent means enabled.
  static const sourceCode = 'barcode_list';
  static const displayName = 'barcode-list.ru';
  static const websiteUrl = 'https://barcode-list.ru';

  static const _timeout = Duration(seconds: 10);

  final log = Logger('BarcodeListDataSource');

  final http.Client Function() _clientFactory;

  BarcodeListDataSource({http.Client Function()? clientFactory})
    : _clientFactory = clientFactory ?? http.Client.new;

  static Uri searchUri(String barcode) => Uri.https(
    'barcode-list.ru',
    '/barcode/RU/Поиск.htm',
    {'barcode': barcode},
  );

  /// Null when the site has no name for [barcode] or cannot be reached. A
  /// missing name is never an error for the caller: the scan flow carries on
  /// exactly as it did before this lookup existed.
  Future<BarcodeListResult?> lookUp(String barcode) async {
    final inner = _clientFactory();
    final client = ONTHttpClient(await AppConst.getUserAgentString(), inner);
    try {
      final response = await client.get(searchUri(barcode)).timeout(_timeout);
      if (response.statusCode != 200) {
        log.warning('barcode-list.ru HTTP ${response.statusCode}');
        return null;
      }
      return parse(barcode, response.body);
    } catch (error) {
      log.warning('barcode-list.ru lookup failed: $error');
      return null;
    } finally {
      // The wrapper's close() is BaseClient's no-op; the real client is the
      // one holding the connection.
      inner.close();
    }
  }

  static final _titlePattern = RegExp(
    r'<title>(.*?) - Штрих-код:',
    dotAll: true,
  );
  static final _tablePattern = RegExp(
    r'<table\s+class="randomBarcodes">(.*?)</table>',
    dotAll: true,
  );
  static final _rowPattern = RegExp(
    r'<tr[^>]*>\s*<td[^>]*>\s*\d+\s*</td>\s*'
    r'<td[^>]*>\s*(\d+)\s*</td>\s*'
    r'<td[^>]*>(.*?)</td>\s*'
    r'<td[^>]*>(.*?)</td>\s*'
    r'<td[^>]*>\s*(\d+)\s*</td>',
    dotAll: true,
  );

  /// Reads a search result page. Rows are kept only when their code is the
  /// one asked for, so a stray table of other codes never names this one.
  static BarcodeListResult? parse(String barcode, String html) {
    final table = _tablePattern.firstMatch(html)?.group(1);
    if (table == null) return null;

    final wanted = _stripLeadingZeros(barcode);
    final variants = <BarcodeListName>[
      for (final row in _rowPattern.allMatches(table))
        if (_stripLeadingZeros(row.group(1)!) == wanted)
          BarcodeListName(
            _clean(row.group(2)!),
            _clean(row.group(3)!),
            int.parse(row.group(4)!),
          ),
    ]..removeWhere((variant) => variant.name.isEmpty);
    if (variants.isEmpty) return null;
    variants.sort((a, b) => b.rating.compareTo(a.rating));

    final title = _titlePattern.firstMatch(html)?.group(1);
    final bestName = title != null && _clean(title).isNotEmpty
        ? _clean(title)
        : variants.first.name;
    return BarcodeListResult(barcode, bestName, variants);
  }

  static String _stripLeadingZeros(String code) =>
      code.replaceFirst(RegExp(r'^0+'), '');

  static String _clean(String text) => _decodeEntities(
    text.replaceAll(RegExp(r'<[^>]*>'), ''),
  ).replaceAll(RegExp(r'\s+'), ' ').trim();

  static const _namedEntities = {
    'quot': '"',
    'amp': '&',
    'lt': '<',
    'gt': '>',
    'apos': "'",
    'nbsp': ' ',
    'laquo': '«',
    'raquo': '»',
    'ndash': '–',
    'mdash': '—',
  };

  static String _decodeEntities(String text) => text.replaceAllMapped(
    RegExp(r'&(#x[0-9a-fA-F]+|#\d+|[a-zA-Z]+);'),
    (match) {
      final entity = match.group(1)!;
      if (entity.startsWith('#x')) {
        return String.fromCharCode(int.parse(entity.substring(2), radix: 16));
      }
      if (entity.startsWith('#')) {
        return String.fromCharCode(int.parse(entity.substring(1)));
      }
      return _namedEntities[entity] ?? match.group(0)!;
    },
  );
}
