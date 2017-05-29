import sequtils, math, options
import karax, karaxdsl, kdom, vdom, vstyles, jdict, jstrutils

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

    resizerStyle*: VStyle not nil

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

  resizerStyle: VStyle(),

  draggingPanel: none(PanelPath),

  onupdate: discardOnUpdate,
  columns: @[]
)

var mousemoveProc, mouseupProc: proc (ev: Event) {.closure.} = nil

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

proc getWorkingAreaColumnsAmount(config: Config): int =
  var amount = 0
  for column in config.columns:
    if hasColumnWorkingArea(config=config, column=column):
      amount += 1
  return amount

proc insertColumn*(config: var Config; path: ColumnPath; column: Column) =
  config.columns.insert(@[column], path)

proc deleteColumn*(config: var Config; path: ColumnPath) =
  config.columns.delete(path)

proc resizeColumn*(config: var Config; path: ColumnPath; widthPx: int) =
  let column = config.getColumn(path)
  if hasColumnWorkingArea(config=config, column=column):
    let freeSpace = config.width - config.getFixedColumnsWidth()
    let width = int(round(widthPx * 100 / freeSpace))
    let workingAreaColumnsAmount = config.getWorkingAreaColumnsAmount()
    config.columns[path].width = width
    if workingAreaColumnsAmount > 1:
      let widthDiff = int(round((width - column.width) / (workingAreaColumnsAmount - 1)))
      for columnIndex in low(config.columns)..high(config.columns):
        if columnIndex != path:
          config.columns[columnIndex].width -= widthDiff
  else:
    config.columns[path].width = widthPx

proc insertRow*(config: var Config; path: RowPath; row: Row) =
  config.columns[path.columnPath].rows.insert(@[row], path.index)

proc deleteRow*(config: var Config; path: RowPath) =
  config.columns[path.columnPath].rows.delete(path.index)
  if len(config.columns[path.columnPath].rows) == 0:
    deleteColumn(config=config, path=path.columnPath)

proc resizeRow*(config: var Config; path: RowPath; heightPx: int) =
  let row = config.getRow(path)
  let column = config.getColumn(path.columnPath)
  let height = int(round(heightPx * 100 / config.height))
  let heightDiff = int(round((height - row.height) / (len(column.rows) - 1)))
  config.columns[path.columnPath].rows[path.index].height = height
  for rowIndex in low(column.rows)..high(column.rows):
    if rowIndex != path.index:
      config.columns[path.columnPath].rows[rowIndex].height -= heightDiff

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

proc getRowHeightPx(config: Config; row: Row): int =
  int(round(row.height * config.height / 100))

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
  let column = config.getColumn(path.columnPath)
  let row = config.getRow(path)
  let height = config.getRowHeightPx(row)
  let resizerId = cstring"karadock-row-" & &path.columnPath & cstring"-" & &path.index

  let style = style(
    (StyleAttr.position, cstring"relative"),
    (StyleAttr.height, &height & cstring"px")
  ).merge(config.rowStyle(config=config, path=path))

  let resizerStyle = style(
    (StyleAttr.position, cstring"absolute"),
    (StyleAttr.left, cstring"0"),
    (StyleAttr.right, cstring"0"),
    (StyleAttr.bottom, cstring"-5px"),
    (StyleAttr.height, cstring"5px"),
    (StyleAttr.zIndex, cstring"100"),
    (StyleAttr.cursor, cstring"row-resize")
  )

  var resizerStartY: int = 0

  proc onResizerMouseDown(ev: Event; n: VNode) =
    preventDefault(ev)
    resizerStartY = ev.clientY;

    mousemoveProc = proc (ev: Event) =
      document.getElementById(resizerId).applyStyle(resizerStyle.merge(
        style(StyleAttr.bottom, &(resizerStartY - ev.clientY) & cstring"px")
      ).merge(config.resizerStyle))

    mouseupProc =  proc (ev: Event) =
      mousemoveProc = nil
      mouseupProc = nil
      var config = config
      config.resizeRow(path=path, heightPx=height + ev.clientY - resizerStartY)
      config.onupdate(config)

  result = buildHtml(tdiv(style=style)):
    if path.index != high(column.rows):
      tdiv(id=resizerId, style=resizerStyle, onmousedown=onResizerMouseDown)
    if len(row.panels) > 1 or row.panels.any(proc (panel: Panel): bool = panel.forceDisplayName):
      renderRowHeader(config=config, row=row, path=path)
    row.panels[row.activePanel].body

proc renderColumn(config: Config; path: ColumnPath): VNode =
  let column = getColumn(config=config, path=path)
  let width = getColumnWidthPx(config=config, column=column)
  let resizerId = cstring"karadock-column-" & &path

  let columnStyle = style(
    (StyleAttr.display, cstring"inline-block"),
    (StyleAttr.width, &width & "px"),
    (StyleAttr.position, cstring"relative"),
    (StyleAttr.cssFloat, cstring"left")
  ).merge(config.columnStyle(config=config, path=path))

  let resizerStyle = style(
    (StyleAttr.backgroundColor, cstring"transparent"),
    (StyleAttr.position, cstring"absolute"),
    (StyleAttr.right, cstring"-5px"),
    (StyleAttr.top, cstring"0"),
    (StyleAttr.bottom, cstring"0"),
    (StyleAttr.width, cstring"5px"),
    (StyleAttr.zIndex, cstring"100"),
    (StyleAttr.cursor, cstring"col-resize")
  )

  var resizerStartX: int = 0

  proc onResizerMouseDown(ev: Event; n: VNode) =
    preventDefault(cast[kdom.Event](ev))
    resizerStartX = ev.clientX;

    mousemoveProc = proc (ev: Event) =
      document.getElementById(resizerId).applyStyle(resizerStyle.merge(
        style(StyleAttr.right, &(resizerStartX - ev.clientX) & cstring"px")
      ).merge(config.resizerStyle))

    mouseupProc =  proc (ev: Event) =
      mousemoveProc = nil
      mouseupProc = nil
      var config = config
      config.resizeColumn(path=path, widthPx=width + (ev.clientX - resizerStartX))
      config.onupdate(config)

  result = buildHtml(tdiv(style=columnStyle)):
    if path != high(config.columns):
      tdiv(id=resizerId, style=resizerStyle, onmousedown=onResizerMouseDown)
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

document.addEventListener(cstring"mousemove", proc(event: Event) =
  if mousemoveProc != nil:
    preventDefault(event)
    mousemoveProc(event)
)

document.addEventListener(cstring"mouseup", proc(event: Event) =
  if mouseupProc != nil:
    mouseupProc(event)
)
