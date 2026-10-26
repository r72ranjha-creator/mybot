import 'dart:convert';
import 'dart:io';

import 'package:csv/csv.dart';
import 'package:excel/excel.dart';
import 'package:path/path.dart' as p;

class ExtractedDocument {
  ExtractedDocument({
    required this.text,
    required this.kind,
    this.pageCount,
    this.meta = const {},
  });

  final String text;
  final String kind;
  final int? pageCount;
  final Map<String, String> meta;

  String get preview => text.length > 400 ? '${text.substring(0, 400)}…' : text;
}

/// Pulls text out of the formats the brief asks for, keeping enough structure
/// that the analyst bot can answer "what is the total" and cite a page.
class FileExtractor {
  static const _maxChars = 120000;

  Future<ExtractedDocument?> extract(String path, String extension) async {
    final ext = extension.toLowerCase().replaceFirst('.', '');
    try {
      return switch (ext) {
        'pdf' => null, // sent to the model as a document instead
        'csv' => await _csv(path),
        'xlsx' || 'xls' => await _excel(path),
        'txt' || 'md' || 'markdown' || 'json' || 'log' => await _plain(path),
        _ => await _plain(path),
      };
    } catch (error) {
      return ExtractedDocument(
        text: 'Is file se text nahi nikla ($error).',
        kind: ext,
      );
    }
  }

  Future<ExtractedDocument> _plain(String path) async {
    final file = File(path);
    final text = await file.readAsString();
    return ExtractedDocument(
      text: _trim(text),
      kind: 'text',
      meta: {'name': p.basename(path)},
    );
  }

  Future<ExtractedDocument> _csv(String path) async {
    final raw = await File(path).readAsString();
    final rows = const CsvToListConverter(
      shouldParseNumbers: false,
      eol: '\n',
    ).convert(raw);
    if (rows.isEmpty) {
      return ExtractedDocument(text: '(empty csv)', kind: 'csv');
    }
    final header = rows.first.map((cell) => '$cell').toList();
    final body = rows.skip(1).take(200).toList();
    final buffer = StringBuffer()
      ..writeln('Columns: ${header.join(' | ')}')
      ..writeln('Rows: ${rows.length - 1}')
      ..writeln('Sample:');
    for (final row in body) {
      buffer.writeln(row.map((cell) => '$cell').join(' | '));
    }
    return ExtractedDocument(
      text: _trim(buffer.toString()),
      kind: 'csv',
      meta: {'columns': '${header.length}', 'rows': '${rows.length - 1}'},
    );
  }

  Future<ExtractedDocument> _excel(String path) async {
    final bytes = await File(path).readAsBytes();
    final book = Excel.decodeBytes(bytes);
    final buffer = StringBuffer();
    var totalRows = 0;
    for (final name in book.tables.keys) {
      final sheet = book.tables[name]!;
      totalRows += sheet.maxRows;
      buffer.writeln('--- sheet "$name" (${sheet.maxRows} rows) ---');
      var printed = 0;
      for (final row in sheet.rows) {
        final cells = row
            .map((cell) => cell?.value?.toString() ?? '')
            .toList();
        if (cells.every((cell) => cell.isEmpty)) continue;
        buffer.writeln(cells.join(' | '));
        printed++;
        if (printed >= 60) {
          buffer.writeln('… (truncated)');
          break;
        }
      }
    }
    return ExtractedDocument(
      text: _trim(buffer.toString()),
      kind: 'xlsx',
      meta: {'sheets': '${book.tables.length}', 'rows': '$totalRows'},
    );
  }

  String _trim(String text) {
    final collapsed = text.replaceAll(RegExp(r'\n{3,}'), '\n\n').trim();
    if (collapsed.length <= _maxChars) return collapsed;
    return '${collapsed.substring(0, _maxChars)}\n… (file truncated for analysis)';
  }

  /// CSV rows as structured data for arithmetic questions.
  Future<List<List<String>>> csvRows(String path) async {
    final raw = await File(path).readAsString();
    final rows = const CsvToListConverter(shouldParseNumbers: false, eol: '\n')
        .convert(raw);
    return rows.map((row) => row.map((cell) => '$cell').toList()).toList();
  }

  static String prettySize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  static String utf8Preview(List<int> bytes) =>
      utf8.decode(bytes, allowMalformed: true);
}
