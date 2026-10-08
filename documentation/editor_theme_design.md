# 编辑器主题色设计

## 目标

编辑器的内置 UI、Markdown 装饰、表格、工具栏、菜单及后续新增的 node，共用一份 `EditorColorScheme`。组件根据颜色的**用途**取值，不拥有另一套默认色。默认色板由编辑器自身定义，不读取宿主 Material `ColorScheme`。

这份设计只统一颜色。字号、间距、边框宽度、图标和组件行为仍由 `EditorStyle`、`TableStyle` 等配置。

## 基础语义色

已定义面向整个编辑器的 `EditorColorScheme`，并保留 `MDEditorColorScheme` 作为兼容入口。`brightness` 由浅色/深色构造器显式指定，不从某一个颜色的亮度猜测。

| 字段 | 用途 | 当前主要来源 |
| --- | --- | --- |
| `background` | 编辑区画布 | `MDEditorColorScheme.background` |
| `foreground` | 正文及画布上的默认图标 | `MDEditorColorScheme.foreground` |
| `surface` | 菜单、弹层、工具栏表面 | 菜单和工具栏各自的背景色 |
| `onSurface` | 表面上的文字和图标 | 菜单和工具栏各自的前景色 |
| `subtleSurface` | 代码块、表格首行和轻强调区域 | `subtleBackground`、灰色叠层 |
| `mutedForeground` | 占位文字、辅助标签、弱化图标 | `mutedForeground`、各组件的灰色 |
| `primary` | 光标、链接、选中轮廓、主要操作 | 编辑器色板与组件专用主色 |
| `onPrimary` | 主色按钮上的文字和图标 | 组件各自的白色或黑色 |
| `border` | 普通分隔线与边框 | `border`、表格和工具栏边框色 |
| `selection` | 文本及表格选择底色 | `selectionColor`、组件专用主色透明层 |
| `error` | 删除操作、无效链接等危险状态 | 组件各自的红色 |
| `highlight` | Markdown 高亮和搜索匹配 | `highlightBackground`、搜索样式 |

初版明暗预设沿用现有 Markdown 色板的视觉基调，补齐其他组件需要的语义色：

| 字段 | 浅色 | 深色 |
| --- | --- | --- |
| `background` | `#FFFFFF` | `#1E1F22` |
| `foreground` | `#202124` | `#E7E7EA` |
| `surface` | `#FFFFFF` | `#282E3A` |
| `onSurface` | `#202124` | `#E7E7EA` |
| `subtleSurface` | `#F1F2F5` | `#2A2B30` |
| `mutedForeground` | `#7A7D85` | `#9A9CA5` |
| `primary` | `#5B5BD6` | `#A8A7FF` |
| `onPrimary` | 根据 `primary` 自动选择白或黑 | 根据 `primary` 自动选择白或黑 |
| `border` | `#D7D9E0` | `#44464E` |
| `selection` | `#245B5BD6` | `#38A8A7FF` |
| `error` | `#E53935` | `#FF8A80` |
| `highlight` | `#80FFEB3B` | `#99FFD54F` |

`tagBackground`、`tagBorder`、hover、表格条纹等不是新的基础字段。它们由 `primary`、`surface`、`subtleSurface` 等组合产生，集中在 scheme 的语义 getter 中，例如 `tagBackground` 和 `tableStripeBackground`。计算时在实际底色上混合，避免直接使用固定 alpha 在深色背景上失去对比。

`selection` 和 `onPrimary` 虽可显式覆盖，但默认必须随 `primary` 生成。只修改品牌主色时，也重新计算这两个依赖色，不能留下旧主题的选区色或按钮文字色。完整构造器供确实需要逐项指定的应用使用。

代码语法高亮确实需要区分关键字、字符串、数字、注释和键名。把这五个角色放在同一色板的可选 `syntax` 子组中；默认子组由明暗预设生成。它不是代码组件持有的第二个主题入口。

## 单一解析流程

```dart
final colors = explicitEditorColors ?? const EditorColorScheme.light();

// 所有 editor node 和内置组件
final colors = EditorTheme.of(context);

// 没有 BuildContext 的命令
final colors = editorState.editorStyle.colorScheme;
```

`MDEditor` 和 `AppFlowyEditor` 在 build 时解析一次色板，向编辑器子树提供 `EditorTheme`，并把**同一实例**同步给 `EditorState`。不要让组件分别决定是读 `Theme.of(context)` 还是 `EditorState.editorStyle.colorScheme`。Material 原生控件若需 `ThemeData`，在编辑器边界从已解析色板生成局部 Material theme。

优先级为：显式的内容颜色或 node 色彩 token > 现有组件显式颜色参数 > 显式的编辑器 `EditorColorScheme` > 编辑器内置浅色预设。迁移期保留 `EditorStyle.cursorColor`、`selectionColor`、`SelectionMenuStyle` 等显式覆盖参数；它们未传入时从色板取值。

现有 `MDEditor.frontGroundColor` 和 `backgroundColor` 保留兼容，但改成可判断“未传入”的可空参数。旧 `frontGroundColor` 继续影响光标主色以兼容已有调用；新代码应传入完整色板。

深色模式需显式传入 `EditorColorScheme.dark()` 或其自定义版本。宿主 Material 主题的切换不会隐式改变编辑器颜色。

```dart
// 默认：编辑器内置浅色，不受 MaterialApp.theme.colorScheme 影响。
MDEditor(controller: controller);

// 显式深色。
MDEditor(
  controller: controller,
  colorScheme: const EditorColorScheme.dark(),
);

// 只改主色时，选区色和 onPrimary 会一起重新计算。
AppFlowyEditor(
  editorState: state,
  editorStyle: EditorStyle.desktop(
    colorScheme: const EditorColorScheme.light(primary: Color(0xFF006D77)),
  ),
);
```

## 各组件映射

| 组件 | 默认颜色规则 |
| --- | --- |
| 正文、占位文字、链接 | `foreground`、`mutedForeground`、`primary` |
| 光标、拖拽手柄、选区、拖放指示 | `primary`、`selection` |
| Markdown 标签、待办框、高亮 | scheme 的语义 getter，最终只依赖基础色 |
| 代码块 | `subtleSurface`、`border`、`foreground`，语法 token 使用 `syntax` |
| 表格 | 普通底色 `background`；首行/首列 `subtleSurface`；条纹和 hover 用语义 getter；选区用 `selection`/`primary`；边框用 `border` |
| 斜杠菜单、表格菜单、浮动及移动工具栏 | `surface`、`onSurface`、`primary`、`onPrimary`、`border`、`error` |
| 搜索匹配 | `highlight`；当前匹配的轮廓可用 `primary` |

新增 node 的颜色代码只依赖 `EditorTheme.of(context)`，或在没有 context 的操作中依赖 `editorState.editorStyle.colorScheme`。只有用户选择的**内容颜色**可以写入文档；默认 UI 颜色不写入 node 属性。

## 文档颜色与主题切换

当前文字和表格的手动配色会把十六进制颜色写入文档。旧文档的这种颜色继续按原值显示。以后如需“随主题变化的内容颜色”，在相同属性中支持稳定的语义 token（例如 `theme.primary`），读取时解析；导入旧十六进制值时保持兼容。不要在主题切换时改写文档数据。

切换主题或同明暗模式下切换品牌色时，解析后的色板必须更新正文、表格、菜单和当前打开的 Overlay。现在浮动工具栏只把 brightness 变化作为重建条件，需要改为比较完整色板或直接让 Overlay 订阅统一主题。两个并列编辑器可以使用不同的色板，不能依赖全局单例。

## 迁移顺序与验收

1. 定义 `EditorColorScheme` 的不可变值、`copyWith`、浅色/深色预设及派生 getter；保留 `MDEditorColorScheme` 兼容入口。
2. 在 `MDEditor`/`AppFlowyEditor` 建立唯一解析点和 `EditorTheme` 范围，处理 `EditorState` 及 Overlay 的同步。
3. 迁移正文与 Markdown、表格、菜单和工具栏、代码语法高亮；移除各组件未显式传入时的固定色值。尺寸等非颜色配置继续保留。
4. 更新示例和定制文档，提供内置浅色、显式深色及品牌色三种用法。

验收覆盖：默认亮/暗模式；仅传自定义 `primary`；运行时切换颜色但 brightness 不变；菜单打开时切换主题；同屏两个不同色板的编辑器；用户保存的十六进制内容颜色与语义 token；文本、按钮和选区在各自背景上的可读性。
