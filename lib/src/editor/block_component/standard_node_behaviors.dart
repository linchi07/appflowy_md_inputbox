import 'package:appflowy_editor/src/editor/block_component/table_block_component/table_block_component.dart';
import 'package:appflowy_editor/src/editor/block_component/table_block_component/table_cell_block_component.dart';
import 'package:appflowy_editor/src/editor/block_component/table_block_component/table_commands.dart';
import 'package:appflowy_editor/src/editor/block_component/table_block_component/table_node.dart';
import 'package:appflowy_editor/src/editor/editor_component/service/node_behavior.dart';

/// Behaviors of the bundled structured blocks. EditorState dispatches these
/// through NodeBehavior without knowing their document types.
final Map<String, NodeBehavior> standardNodeBehaviors = {
  TableBlockKeys.type: NodeBehavior(
    atomic: true,
    serialize: (node) => TableNode(node: node).toMarkdown(),
    commandShortcuts: tableCommands,
  ),
  TableCellBlockKeys.type: const NodeBehavior(preventMergeAtStart: true),
};
