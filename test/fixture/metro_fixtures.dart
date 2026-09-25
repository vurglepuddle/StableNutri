/// METRO GraphQL answers (supergraph.metro-cc.ru), captured 2026-09-26 and
/// trimmed to the attributes the app reads plus two it ignores.
library;

/// `findByBarcode('4601751024794')`: one cheese with full КБЖУ.
const metroNaturaAnswer = '''
{"data":{"search":{"products":{"products":[{
  "id":530877445,
  "name":"Сыр Natura Сливочный полутвердый нарезка 45%, 150г",
  "url":"/products/150g-syr-slivochnyy-45-natura-narezka-bzmzh",
  "images":["https://cdn.metro-cc.ru/ru/ru_pim_163825001001_01.png","https://cdn.metro-cc.ru/ru/ru_pim_163825001001_02.png"],
  "barcodes":["4601751024794"],
  "manufacturer":{"name":"NATURA"},
  "attributes":[
    {"name":"Тип","text":"Сыр"},
    {"name":"Вес, объем","text":"150"},
    {"name":"Белки, г","text":"25"},
    {"name":"Жиры, г","text":"26"},
    {"name":"Углеводы, г","text":"0.0"},
    {"name":"Энергетическая ценность, ккал/100 г","text":"340"},
    {"name":"Бренд","text":"NATURA"}
  ]
}]}}}}
''';

/// A drink sold by volume, with several barcodes.
const metroColaAnswer = '''
{"data":{"search":{"products":{"products":[{
  "id":1,
  "name":"Напиток Coca-Cola Original газированный, 330мл",
  "url":"/products/coca-cola-330",
  "images":[],
  "barcodes":["4631164152289","5449000000996","4627170090271"],
  "manufacturer":{"name":"Coca-Cola"},
  "attributes":[
    {"name":"Вес, объем","text":"330"},
    {"name":"Белки, г","text":"0.0"},
    {"name":"Жиры, г","text":"0.0"},
    {"name":"Углеводы, г","text":"10,6"},
    {"name":"Энергетическая ценность, ккал/100 г","text":"42"}
  ]
}]}}}}
''';

const metroEmptyAnswer = '{"data":{"search":{"products":{"products":[]}}}}';
