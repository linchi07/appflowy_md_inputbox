# 编辑器菜单

编辑器的下拉菜单、搜索选择器、右键菜单和 Markdown 菜单共用以下组件：

| 组件 | 职责 |
| --- | --- |
| `EditorMenuSurface` | 面板背景、圆角、阴影、默认字体与图标颜色 |
| `EditorMenuItem` | 行高、文字和图标布局、悬停、选中与禁用状态 |
| `EditorMenuTextField` | 搜索及表单输入框的边框、背景、光标、文字与占位颜色 |
| `EditorMenuList` | 菜单分组、过滤、键盘选择与滚动 |
| `EditorPopoverMenu.show` | 锚点定位、屏幕边界、点击外部关闭与焦点恢复 |

默认颜色来自 `EditorTheme`，没有主题上下文时使用编辑器内置浅色色板。`SelectionMenuStyle` 保留为现有调用的显式颜色覆盖；其定义已移动到 `editor_menu_style.dart`，旧导入路径继续导出它。

标准菜单面板圆角为 6，菜单项圆角为 4，行高为 38，字号为 12。下拉、搜索结果及右键菜单都通过共享组件使用这些值。内置菜单不调用 `showSearch`、`SearchDelegate`、`showMenu` 或 `PopupMenuButton`。

## 新增下拉或搜索选择器

```dart
final anchor = EditorPopoverMenu.anchorRect(buttonContext);
if (anchor == null) return;

EditorPopoverMenu.show(
  context: buttonContext,
  anchor: anchor,
  colors: editorState.editorStyle.colorScheme,
  style: editorState.editorStyle.selectionMenuStyle,
  // 省略 searchHint 即为普通下拉菜单。
  searchHint: '搜索语言',
  entries: [
    EditorMenuEntry(
      label: 'Dart',
      searchKeywords: const ['dart'],
      selected: language == 'dart',
      onSelected: () => setLanguage('dart'),
    ),
  ],
);
```

搜索检查 `label` 和 `searchKeywords`，忽略大小写和查询首尾空格。上下方向键循环选择可用项，自动滚动到当前项；Enter 执行动作，Esc 或点击面板外部关闭菜单。关闭后恢复原来的焦点。`onDismiss` 可用于释放编辑器的焦点保留计数。

传入的 `anchor` 使用全局坐标。菜单进入 root Overlay 时会携带编辑器色板，避免读取 Overlay 外的宿主默认配色。动作会在旧菜单关闭后执行，因此动作可以打开后续菜单。

## 右键和复杂菜单

`AppFlowyEditor` 和 `MDEditor` 默认使用 `defaultContextMenuBuilder`。它将剪切、复制、粘贴转换为同一套 `EditorMenuEntry`，按当前位置显示，并限制在屏幕边界内。传入自定义 `contextMenuBuilder` 可以替换内容；显式传入 `null` 可以关闭编辑器右键菜单。

保留 `ContextMenuItem.isApplicable` 的过滤行为；空分组不会产生分隔线。复杂的链接、颜色及查找面板使用共享面板和输入框，其已有表单验证、颜色值和编辑命令继续由各功能处理。

`EditorMenuTextField` 自身的剪贴板菜单也使用共享面板和菜单项。动作与本地化标签来自 `EditableTextState`，保留输入框原有的复制、剪切、粘贴等编辑语义，并使用编辑器色板显示选区。

Markdown 斜杠菜单仍负责斜杠及查询文本的编辑行为，并使用共享面板和菜单行。不要为了新菜单再创建一份背景、圆角、hover 或输入框默认值；在现有组件上添加内容和行为即可。
