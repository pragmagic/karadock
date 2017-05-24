import sequtils, math, options
import vdom, vstyles, components, karax, karaxdsl, jdict, jstrutils

type
  ColumnPath* = Natural

  RowPath* = tuple
    columnPath: ColumnPath
    index: Natural

  PanelPath* = tuple
    rowPath: RowPath
    index: Natural

  ColumnStyle* = proc(config: Config; path: ColumnPath): VStyle
  RowStyle* = proc(config: Config; path: RowPath): VStyle
  PanelStyle* = proc(config: Config; path: PanelPath): VStyle

  Panel* = object
    name*: cstring not nil
    isWorkingArea*: bool
    forceDisplayName*: bool
    minWidthPx*: int
    minHeightPx*: int
    body*: VNode

  Row* = object
    panels*: seq[Panel] not nil
    activePanel*: Natural
    height*: int #NOTE: Percents

  Column* = object
    rows*: seq[Row] not nil
    width*: int #NOTE: Will be in percents for any column which has working area panel

  Config* = object
    width*: int
    height*: int

    columnStyle*: ColumnStyle not nil
    columnDropPlaceholderStyle*: ColumnStyle not nil

    rowStyle*: RowStyle not nil
    rowHeaderStyle*: RowStyle not nil
    rowDropPlaceholderStyle*: RowStyle not nil

    panelNameStyle*: PanelStyle not nil
    panelNameDropPlaceholderStyle*: PanelStyle not nil

    draggingPanel*: Option[PanelPath] #NOTE: Should be replaced by https://developer.mozilla.org/en-US/docs/Web/API/DataTransfer but it's not supported by Karax because not in HTML5

    onupdate*: proc (config: Config) not nil
    columns*: seq[Column] not nil

proc emptyColumnStyle(config: Config; path: ColumnPath): VStyle = VStyle()
proc emptyRowStyle(config: Config; path: RowPath): VStyle = VStyle()
proc emptyPanelStyle(config: Config; path: PanelPath): VStyle = VStyle()

proc discardOnUpdate*(config: Config) = discard

let initialConfig* = Config(
  width: 0,
  height: 0,

  columnStyle: emptyColumnStyle,
  columnDropPlaceholderStyle: emptyColumnStyle,

  rowStyle: emptyRowStyle,
  rowHeaderStyle: emptyRowStyle,
  rowDropPlaceholderStyle: emptyRowStyle,

  panelNameStyle: emptyPanelStyle,
  panelNameDropPlaceholderStyle: emptyPanelStyle,

  draggingPanel: none(PanelPath),

  onupdate: discardOnUpdate,
  columns: @[]
)

proc getColumn*(config: Config; path: ColumnPath): Column =
  config.columns[path]

proc getRow*(config: Config; path: RowPath): Row =
  getColumn(config=config, path=path.columnPath).rows[path.index]

proc getPanel*(config: Config; path: PanelPath): Panel =
  getRow(config=config, path=path.rowPath).panels[path.index]

proc findPanelByName*(config: Config; name: cstring): Option[PanelPath] =
  for c, column in pairs(config.columns):
    for r, row in pairs(column.rows):
      for p, panel in pairs(row.panels):
        if panel.name == name:
          return some((
            rowPath: (
              columnPath: Natural(c),
              index: Natural(r)
            ),
            index: Natural(p)
          ))

proc insertColumn*(config: var Config; path: ColumnPath; column: Column) =
  config.columns.insert(@[column], path)

proc deleteColumn*(config: var Config; path: ColumnPath) =
  config.columns.delete(path)

proc resizeColumn*(config: var Config; path: ColumnPath; width: int) =
  config.columns[path].width = width

proc insertRow*(config: var Config; path: RowPath; row: Row) =
  config.columns[path.columnPath].rows.insert(@[row], path.index)

proc deleteRow*(config: var Config; path: RowPath) =
  config.columns[path.columnPath].rows.delete(path.index)
  if len(config.columns[path.columnPath].rows) == 0:
    deleteColumn(config=config, path=path.columnPath)

proc insertPanel*(config: var Config; path: PanelPath; panel: Panel) =
  config.columns[path.rowPath.columnPath].rows[path.rowPath.index].panels.insert(@[panel], path.index)

proc setActivePanel*(config: var Config; path: PanelPath) =
  assert path.index < len(config.columns[path.rowPath.columnPath].rows[path.rowPath.index].panels)
  config.columns[path.rowPath.columnPath].rows[path.rowPath.index].activePanel = path.index

proc deletePanel*(config: var Config; path: PanelPath) =
  config.columns[path.rowPath.columnPath].rows[path.rowPath.index].panels.delete(path.index)
  if len(config.columns[path.rowPath.columnPath].rows[path.rowPath.index].panels) == 0:
    deleteRow(config=config, path=path.rowPath)

proc setPanelBody*(config: var Config; path: PanelPath, body: VNode) =
  config.columns[path.rowPath.columnPath].rows[path.rowPath.index].panels[path.index].body = body

proc movePanel*(config: var Config; src: PanelPath, dst: PanelPath) =
  let panel = getPanel(config=config, path=src)
  deletePanel(config=config, path=src)
  var dst = dst
  if src.rowPath == dst.rowPath and src.index < dst.index:
    dst = (
      rowPath: dst.rowPath,
      index: Natural(dst.index - 1)
    )
  insertPanel(config=config, path=dst, panel=panel)

proc movePanel*(config: var Config; src: PanelPath, dst: RowPath) =
  insertRow(config=config, path=dst, Row(
    panels: @[],
    activePanel: 0
  ))
  movePanel(config=config, src=src, dst=(
    rowPath: dst,
    index: Natural(0)
  ))

proc movePanel*(config: var Config; src: PanelPath, dst: ColumnPath) =
  let panel = getPanel(config=config, path=src)
  insertColumn(config=config, path=dst, Column(
    rows: @[],
    width: panel.minWidthPx
  ))
  let rowPath = (
    columnPath: dst,
    index: Natural(0)
  )
  movePanel(config=config, src=src, dst=rowPath)
  config.columns[rowPath.columnPath].rows[rowPath.index].height = panel.minHeightPx

proc hasColumnWorkingArea(config: Config; column: Column): bool =
  column.rows.any(proc (row: Row): bool =
    row.panels.any(proc (panel: Panel): bool =
      panel.isWorkingArea
    )
  )

proc getFixedColumnsWidth(config: Config): int =
  var width = 0
  for column in config.columns:
    if not hasColumnWorkingArea(config=config, column=column):
      width += column.width
  return width

proc getColumnWidthPx(config: Config; column: Column): int =
  if hasColumnWorkingArea(config=config, column=column):
    let freeSpace = config.width - getFixedColumnsWidth(config=config)
    return int(round(column.width * freeSpace / 100))
  else:
    return column.width

proc renderRowHeaderItem(config: Config; row: Row; panel: Panel; path: PanelPath): VNode =
  proc onClick(ev: Event; n: VNode) =
    if row.activePanel != path.index:
      var config = config
      config.setActivePanel(path=path)
      config.onupdate(config)

  proc onDragStart(ev: Event; n: VNode) =
    var config = config
    config.draggingPanel = some(path)
    config.onupdate(config)

  proc onDragEnd(ev: Event; n: VNode) =
    var config = config
    config.draggingPanel = none(PanelPath)
    config.onupdate(config)

  let style = style(
    (StyleAttr.display, cstring"inline-block"),
    (StyleAttr.cursor, cstring"pointer")
  ).merge(config.panelNameStyle(config=config, path=path));

  result = buildHtml(tdiv(style=style, onclick=onClick, ondragstart=onDragStart, ondragend=onDragEnd)):
    text panel.name

proc renderRowHeader(config: Config; row: Row; path: RowPath): VNode =
  result = buildHtml(tdiv(style=config.rowHeaderStyle(config=config, path=path))):
    for panelIndex in low(row.panels)..high(row.panels):
        let panelPath = (
          rowPath: path,
          index: Natural(panelIndex)
        )
        let panel = config.getPanel(path=panelPath)
        renderRowHeaderItem(config=config, row=row, panel=panel, path=panelPath)

proc renderRow(config: Config; path: RowPath): VNode =
  let row = getRow(config=config, path=path)

  let style = style(
    (StyleAttr.position, cstring"relative"),
    (StyleAttr.height, &int(round(row.height * config.height / 100)) & cstring"px")
  ).merge(config.rowStyle(config=config, path=path))

  let resizerStyle = style(
    (StyleAttr.position, cstring"absolute"),
    (StyleAttr.left, cstring"0"),
    (StyleAttr.right, cstring"0"),
    (StyleAttr.top, cstring"-7px"),
    (StyleAttr.height, cstring"7px"),
    (StyleAttr.zIndex, cstring"100"),
    (StyleAttr.cursor, cstring"row-resize")
  )

  result = buildHtml(tdiv(style=style)):
    tdiv(style=resizerStyle)
    if len(row.panels) > 1 or row.panels.any(proc (panel: Panel): bool = panel.forceDisplayName):
      renderRowHeader(config=config, row=row, path=path)
    row.panels[row.activePanel].body

proc renderColumn(config: Config; path: ColumnPath): VNode =
  let column = getColumn(config=config, path=path)

  let style = style(
    (StyleAttr.display, cstring"inline-block"),
    (StyleAttr.width, &getColumnWidthPx(config=config, column=column) & "px"),
    (StyleAttr.position, cstring"relative"),
    (StyleAttr.cssFloat, cstring"left")
  ).merge(config.columnStyle(config=config, path=path))

  let resizerStyle = style(
    (StyleAttr.position, cstring"absolute"),
    (StyleAttr.left, cstring"-7px"),
    (StyleAttr.top, cstring"0"),
    (StyleAttr.bottom, cstring"0"),
    (StyleAttr.width, cstring"7px"),
    (StyleAttr.zIndex, cstring"100"),
    (StyleAttr.cursor, cstring"col-resize")
  )

  result = buildHtml(tdiv(style=style)):
    tdiv(style=resizerStyle)
    for rowIndex in low(column.rows)..high(column.rows):
      renderRow(config=config, path=(
        columnPath: path,
        index: Natural(rowIndex)
      ))

proc karaDock*(config: Config = initialConfig): VNode =
  let style = style(
    (StyleAttr.width, &config.width & cstring"px"),
    (StyleAttr.height, &config.height & cstring"px"),
  )
  result = buildHtml(tdiv(style=style)):
    for path in low(config.columns)..high(config.columns):
      renderColumn(config=config, path=path)