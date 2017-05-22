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

  Panel* = object
    name*: cstring
    isWorkingArea*: bool
    forceDisplayName*: bool
    minWidthPx*: int
    minHeightPx*: int
    body*: VNode

  Row* = object
    panels*: seq[Panel]
    activePanel*: Natural
    height*: int #NOTE: Percents

  Column* = object
    rows*: seq[Row]
    width*: int #NOTE: Will be in percents for any column which has working area panel

  Config* = object
    width*: int
    height*: int

    columnStyle*: VStyle
    columnDropPlaceHolderStyle: VStyle

    rowStyle*: VStyle
    rowHeaderStyle*: VStyle
    rowDropPlaceHolderStyle*: VStyle

    panelNameStyle*: VStyle
    panelNameDropPlaceHolderStyle: VStyle

    draggingPanel*: Option[PanelPath] #NOTE: Should be replaced by https://developer.mozilla.org/en-US/docs/Web/API/DataTransfer but it's not supported by Karax because not in HTML5

    onupdate*: proc (config: Config) not nil
    columns*: seq[Column]

let initialConfig* = Config(
  width: 0,
  height: 0,

  columnStyle: VStyle(),
  columnDropPlaceHolderStyle: VStyle(),

  rowStyle: VStyle(),
  rowHeaderStyle: VStyle(),
  rowDropPlaceHolderStyle: VStyle(),

  panelNameStyle: VStyle(),
  panelNameDropPlaceHolderStyle: VStyle(),

  draggingPanel: none(PanelPath),

  onupdate: proc(config: Config) = discard,
  columns: @[]
)

proc getColumn*(config: var Config; path: ColumnPath): var Column =
  config.columns[path]

proc getColumn*(config: Config; path: ColumnPath): Column =
  config.columns[path]

proc getRow*(config: var Config; path: RowPath): var Row =
  getColumn(config=config, path=path.columnPath).rows[path.index]

proc getRow*(config: Config; path: RowPath): Row =
  getColumn(config=config, path=path.columnPath).rows[path.index]

proc getPanel*(config: var Config; path: PanelPath): var Panel =
  getRow(config=config, path=path.rowPath).panels[path.index]

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
  getColumn(config=config, path=path).width = width

proc insertRow*(config: var Config; path: RowPath; row: Row) =
  getColumn(config=config, path=path.columnPath).rows.insert(@[row], path.index)

proc deleteRow*(config: var Config; path: RowPath) =
  var column = getColumn(config=config, path=path.columnPath)
  column.rows.delete(path.index)
  if len(column.rows) == 0:
    deleteColumn(config=config, path=path.columnPath)

proc insertPanel*(config: var Config; path: PanelPath; panel: Panel) =
  getRow(config=config, path=path.rowPath).panels.insert(@[panel], path.index)

proc setActivePanel*(config: var Config; path: PanelPath) =
  var row = getRow(config=config, path=path.rowPath)
  assert path.index < len(row.panels)
  row.activePanel = path.index

proc deletePanel*(config: var Config; path: PanelPath) =
  var row = getRow(config=config, path=path.rowPath)
  row.panels.delete(path.index)
  if len(row.panels) == 0:
    deleteRow(config=config, path=path.rowPath)

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
  movePanel(config=config, src=src, dst=(
    columnPath: dst,
    index: Natural(0)
  ))
  var row = getRow(config=config, path=(columnPath: dst, index: Natural(0)))
  row.height = panel.minHeightPx

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

proc renderRowHeader(config: Config; row: Row; path: RowPath): VNode =
  let panelNameStyle = style(
    StyleAttr.display, "inline"
  ).merge(config.panelNameStyle)

  result = buildHtml(tdiv(style=config.rowHeaderStyle)):
    for panelIndex in countup(0, len(row.panels)):
      let panelPath = (
        rowPath: path,
        index: Natural(panelIndex)
      )
      let panel = getPanel(config=config, path=panelPath)

      proc onDragStart(ev: Event; n: VNode) =
        var config = config
        config.draggingPanel = some(panelPath)
        config.onupdate(config)

      proc onDragEnd(ev: Event; n: VNode) =
        var config = config
        config.draggingPanel = none(PanelPath)
        config.onupdate(config)

      tdiv(style=panelNameStyle, ondragstart=onDragStart, ondragend=onDragEnd):
        text panel.name

proc renderRow(config: Config; path: RowPath): VNode =
  let row = getRow(config=config, path=path)

  let style = style(
    (StyleAttr.height, &int(round(row.height * config.height / 100)) & "px"),
  ).merge(config.rowStyle)

  result = buildHtml(tdiv(style=style)):
    if len(row.panels) > 1 or row.panels.any(proc (panel: Panel): bool = panel.forceDisplayName):
      renderRowHeader(config=config, row=row, path=path)
    row.panels[row.activePanel].body

proc renderColumn(config: Config; path: ColumnPath): VNode =
  let column = getColumn(config=config, path=path)

  let style = style(
    (StyleAttr.width, &getColumnWidthPx(config=config, column=column) & "px"),
    (StyleAttr.position, cstring("relative"))
  ).merge(config.columnStyle)

  result = buildHtml(tdiv(style=style)):
    for rowIndex in countup(0, len(column.rows)):
      renderRow(config=config, path=(
        columnPath: path,
        index: Natural(rowIndex)
      ))

proc karaDock*(config: Config = initialConfig): VNode =
  let style = style(
    (StyleAttr.width, &config.width & "px"),
    (StyleAttr.height, &config.height & "px"),
  )
  result = buildHtml(tdiv(style=style)):
    for path in countup(0, len(config.columns)):
      renderColumn(config=config, path=path)