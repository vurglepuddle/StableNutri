/// Trimmed barcode-list.ru search pages, captured 2026-09-26. Markup and
/// whitespace are as served; only unrelated page chrome is cut.
library;

/// 4600493500023 (Карат «Дружба» processed cheese, 230 g). Rows 1, 2 and 5
/// of the real result, plus a row for another code the parser must skip
/// and a row using an HTML entity.
const barcodeListFoundPage = '''
<!DOCTYPE html>
<html>
<head>
<meta http-equiv="Content-Type" content="text/html; charset=utf-8" />
<title>Сыр плав. ванночка Дружба 230гр - Штрих-код: 4600493500023</title>
</head>
<body>
<h1 class="pageTitle" style="text-align: left " >Результаты поиска Штрих-код: 4600493500023</h1>
<table  class="randomBarcodes">
                        <tr>
                            <th style="text-align: right;">№</th>
                            <th style="text-align: left;">Штрих-код</th>
                            <th style="text-align: left;">Наименование</th>
                            <th style="text-align: center;">Единица измерения</th>
                            <th style="text-align: right;">Рейтинг*</th>
                        </tr>
                                                <tr class="even">
                            <td style="text-align: right;">1</td>
                            <td style="text-align: left;"> 4600493500023</td>
                            <td style="text-align: left;"> СЫР ПЛАВ. ВАННОЧКА ДРУЖБА 230ГР</td>
                            <td style="text-align: center;">ШТ.</td>
                            <td style="text-align: right;">4</td>
                        </tr>
                                                <tr class=" odd">
                            <td style="text-align: right;">2</td>
                            <td style="text-align: left;"> 4600493500023</td>
                            <td style="text-align: left;"> СЫР ПЛАВЛЕННЫЙ ДРУЖБА 55% П/К 230Г</td>
                            <td style="text-align: center;">ШТ.</td>
                            <td style="text-align: right;">4</td>
                        </tr>
                                                <tr class="even">
                            <td style="text-align: right;">3</td>
                            <td style="text-align: left;"> 4600493500023</td>
                            <td style="text-align: left;"> СЫР ПЛАВЛЕНЫЙ ДРУЖБА 230Г "КАРАТ"</td>
                            <td style="text-align: center;">ШТ.</td>
                            <td style="text-align: right;">3</td>
                        </tr>
                                                <tr class=" odd">
                            <td style="text-align: right;">4</td>
                            <td style="text-align: left;"> 4600000000000</td>
                            <td style="text-align: left;"> ДРУГОЙ ТОВАР</td>
                            <td style="text-align: center;">ШТ.</td>
                            <td style="text-align: right;">99</td>
                        </tr>
                                                <tr class="even">
                            <td style="text-align: right;">5</td>
                            <td style="text-align: left;"> 4600493500023</td>
                            <td style="text-align: left;"> СЫР &quot;ДРУЖБА&quot; 230 Г</td>
                            <td style="text-align: center;">ШТ.</td>
                            <td style="text-align: right;">1</td>
                        </tr>
                    </table>
</body>
</html>
''';

/// A code the site does not know: no result table at all.
const barcodeListNotFoundPage = '''
<!DOCTYPE html>
<html>
<head>
<meta http-equiv="Content-Type" content="text/html; charset=utf-8" />
<title>Поиск:4600605000170</title>
</head>
<body>
<h1 class="pageTitle" style="text-align: left " >Поиск:4600605000170</h1>
<div>Результаты поиска Штрих-код: 4600605000170</div>
</body>
</html>
''';
