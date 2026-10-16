import 'dart:io';
import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
class AddCopy extends RecursiveAstVisitor<void> {
 final edits=<int>[];
 @override void visitMethodInvocation(MethodInvocation n) {
  if ({'fmtDuration','fmtSleepDuration','fmtTimeOnly','fmtDateTime','fmtWeekday','fmtDateWeekday'}.contains(n.methodName.name) && !n.argumentList.arguments.any((a)=>a is NamedExpression && a.name.label.name=='localizations')) { edits.add(n.argumentList.rightParenthesis.offset); }
  super.visitMethodInvocation(n);
 }
}
void main(List<String> files) { for(final f in files) { var s=File(f).readAsStringSync(); final v=AddCopy();parseString(content:s).unit.accept(v);for(final i in v.edits..sort((a,b)=>b.compareTo(a))) {s=s.substring(0,i)+', localizations: context.l10n'+s.substring(i);}File(f).writeAsStringSync(s); } }
