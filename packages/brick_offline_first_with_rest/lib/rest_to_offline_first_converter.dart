import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart';
import 'package:dart_style/dart_style.dart' as dart_style;

final _formatter = dart_style.DartFormatter();

/// Convert a JSON API payload into an [OfflineFirstModel], output via [generate] or [saveToFile].
///
/// This will not map associations or non-primitive types.
class RestToOfflineFirstConverter {
  /// Fully-qualified http URL with path
  ///
  /// For example, https://api.com/dogs
  final String endpoint;

  /// Any extra headers to pass in the GET call
  final Map<String, String>? headers;

  /// For properties nested one level deep
  ///
  /// For example, `user` in ```{ user: { name:, last_name: ... } }```
  final String? topLevelKey;

  late Client _client;

  /// Only set client when testing
  set client(value) => _client = value;
  Client get client => _client;

  RestToOfflineFirstConverter({
    required this.endpoint,
    this.headers,
    this.topLevelKey,
  }) {
    _client = Client();
    headers?.addAll({'Content-Type': 'application/json'});
  }

  /// Fetch from the rest endpoint
  Future<Map<String, dynamic>> getRestPayload() async {
    final resp = await client.get(Uri.parse(endpoint), headers: headers);
    if (resp.statusCode != 200) {
      throw StateError('Request unsuccessful; status code ${resp.statusCode}');
    }

    final result = jsonDecode(resp.body);
    if (result is List) {
      if (result.first is List) {
        throw StateError("Can't process nested, top-level arrays");
      }
      return result.first;
    } else {
      if (topLevelKey != null) {
        final res = result[topLevelKey];
        if (res is List) {
          return res.first;
        }

        return res;
      }

      return result;
    }
  }

  /// Produce instance fields
  String generateFields(Map<String, dynamic> fields) {
    final keys = fields.keys.toList();
    keys.sort();
    return keys.fold<List<String>>(<String>[], (acc, key) {
      final valueType = fields[key].runtimeType.toString();
      return acc..add('  final $valueType ${toCamelCase(key)};');
    }).join('\n\n');
  }

  /// Produce fields to be invoked in the default constructor
  String generateConstructorFields(Map<String, dynamic> fields) {
    final keys = fields.keys.toList();
    keys.sort();
    return keys.fold<List<String>>(<String>[], (acc, key) {
      return acc..add('    this.${toCamelCase(key)}');
    }).join(',\n');
  }

  /// Output a usable class annotated by `@ConnectOfflineFirstWithRest` and extending [OfflineFirstModel].
  ///
  /// The `restEndpoint` is generated by removing the domain and protocol from [endpoint].
  Future<String> generate([Map<String, dynamic>? _fields]) async {
    final fields = _fields ?? await getRestPayload();
    final generatedFields = generateFields(fields);
    final generatedConstructorFields = generateConstructorFields(fields);
    final splitEndpoint = endpoint.split('/');
    final camelizedClass = toCamelCase(splitEndpoint.last);
    final className = camelizedClass[0].toUpperCase() + camelizedClass.substring(1);
    final restEndpoint = splitEndpoint.sublist(3).join('/');
    final fromKey = topLevelKey != null ? "fromKey: '$topLevelKey'," : '';

    final output = '''
      import 'package:brick_offline_first/offline_first.dart';
      import 'package:brick_offline_first_abstract/annotations.dart';

      @ConnectOfflineFirstWithRest(
        restConfig: RestSerializable(
          fieldRename: FieldRename.snake,
          endpoint: "=> '/$restEndpoint';",$fromKey
        ),
      )
      class $className extends OfflineFirstModel {
      $generatedFields

        $className({
      $generatedConstructorFields,
        });
      }
    ''';

    return _formatter.format(output);
  }

  /// Save generated class to file.
  /// Defaults to `brick/models/LAST_ENDPOINT_PATH.dart`
  Future<File> saveToFile([String? filePath]) async {
    filePath = filePath ?? 'brick/models/${endpoint.split('/').last}.dart';
    final contents = await generate();
    final file = File(filePath);
    return await file.writeAsString(contents);
  }

  /// Converts `a_variable_name` to `aVariableName`
  static String toCamelCase(String input) {
    final contents = input.toLowerCase();
    final snake = RegExp('(.*?)_([a-zA-Z])');
    final kebab = RegExp('(.*?)-([a-zA-Z])');

    return contents
        .replaceAllMapped(snake, _camelizeCallback)
        .replaceAllMapped(kebab, _camelizeCallback);
  }

  static String _camelizeCallback(Match match) {
    return match.group(1)! + match.group(2)![0].toUpperCase() + match.group(2)!.substring(1);
  }
}
