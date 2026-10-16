import 'dart:convert';
import 'dart:io';
import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
class Extract extends RecursiveAstVisitor<void> {
 final String file; final List<Map<String,dynamic>> rows;
 Extract(this.file,this.rows);
 @override void visitSimpleStringLiteral(SimpleStringLiteral n) { emit(n); }
 @override void visitStringInterpolation(StringInterpolation n) { emit(n); }
 @override void visitAdjacentStrings(AdjacentStrings n) { emit(n); }
 void emit(StringLiteral n) {
  final src=n.toSource(); if(!RegExp(r'[가-힣]').hasMatch(src)) return;
  final args=<String>[];
  String flatten(StringLiteral node) {
   if(node is SimpleStringLiteral) return node.value;
   if(node is AdjacentStrings) return node.strings.map(flatten).join();
   if(node is StringInterpolation) return node.elements.map((e) {
    if(e is InterpolationString) return e.value;
    final exp=(e as InterpolationExpression).expression.toSource();
    final index=args.length; args.add(exp); return '{arg$index}';
   }).join();
   throw StateError(src);
  }
  final value=flatten(n);
  final constOffsets=<int>[];
  for(AstNode? p=n.parent; p!=null; p=p.parent) {
    if(p is InstanceCreationExpression && p.keyword?.lexeme=='const') constOffsets.add(p.keyword!.offset);
    if(p is ListLiteral && p.constKeyword!=null) constOffsets.add(p.constKeyword!.offset);
    if(p is SetOrMapLiteral && p.constKeyword!=null) constOffsets.add(p.constKeyword!.offset);
  }
  rows.add({'file':file,'offset':n.offset,'length':n.length,'template':value,'args':args,'parent':n.parent.runtimeType.toString(),'source':src,'constOffsets':constOffsets});
  void nested(StringLiteral node) {
    if(node is AdjacentStrings) { for(final child in node.strings) { nested(child); } }
    if(node is StringInterpolation) { for(final element in node.elements) { if(element is InterpolationExpression) { element.expression.accept(this); } } }
  }
  nested(n);
 }
}
void main(List<String> paths) {
 final rows=<Map<String,dynamic>>[];
 for(final f in paths) { parseString(content:File(f).readAsStringSync()).unit.accept(Extract(f,rows)); }
 File('artifacts/sleep_global_2026_10_14/literal_inventory.json').writeAsStringSync(const JsonEncoder.withIndent('  ').convert(rows));
 print('Extracted '+rows.length.toString()+' literals');
}
