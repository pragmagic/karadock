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

  Panel* = ref object
    name*: cstring not nil
    isWorkingArea*: bool
    forceDisplayName*: bool
    minWidthPx*: int
    minHeightPx*: int
    body*: VNode

  Row* = ref object
    panels*: seq[Panel] not nil
    activePanel*: Natural
    height*: float #NOTE: Percents

  Column* = ref object
    rows*: seq[Row] not nil
    width*: float #NOTE: Will be in percents for any column which has working area panel

  Config* = ref object
    width*: int
    height*: int

    columnStyle*: ColumnStyle not nil
    columnDropPlaceholderStyle*: ColumnStyle not nil

    rowStyle*: RowStyle not nil
    rowHeaderStyle*: RowStyle not nil
    rowDropPlaceholderStyle*: RowStyle not nil

    panelNameStyle*: PanelStyle not nil
    panelNameDropPlaceholderStyle*: PanelStyle not nil
    panelBodyStyle*: PanelStyle not nil

    resizerStyle*: VStyle not nil

    onupdate*: proc (config: Config) not nil
    columns*: seq[Column] not nil

{.experimental.}

using
  event: Event
  node: VNode
  config: Config

var draggingPanel: Option[PanelPath] = none(PanelPath)
var dragOverId: cstring = nil

var mousemoveProc, mouseupProc: proc (ev: Event) {.closure.} = nil

proc getColumn*(config; path: ColumnPath): Column =
  config.columns[path]

proc getRow*(config; path: RowPath): Row =
  config.getColumn(path.columnPath).rows[path.index]

proc getPanel*(config; path: PanelPath): Panel =
  config.getRow(path.rowPath).panels[path.index]

proc findPanel*(config; name: cstring): Option[PanelPath] =
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

proc findPanelColumn*(config; panelName: cstring): Option[ColumnPath] =
  for c, column in pairs(config.columns):
    for r, row in pairs(column.rows):
      for p, panel in pairs(row.panels):
        if panel.name == panelName:
          return some(ColumnPath(c))

proc hasColumnWorkingArea(config; column: Column): bool =
  column.rows.any(proc (row: Row): bool =
    row.panels.any(proc (panel: Panel): bool =
      panel.isWorkingArea
    )
  )

proc getFixedColumnsWidth(config: Config): float =
  var width: float = 0
  for column in config.columns:
    if not config.hasColumnWorkingArea(column):
      width += column.width
  return width

proc getColumnWidthPx(config; column: Column): float =
  if config.hasColumnWorkingArea(column):
    let freeSpace = float(config.width) - config.getFixedColumnsWidth()
    return column.width * float(freeSpace) / 100
  else:
    return column.width

proc getColumnMinWidthPx*(config; column: Column): int =
  result = high(int)
  for row in column.rows:
    for panel in row.panels:
      if panel.minWidthPx < result:
        result = panel.minWidthPx

proc getWorkingAreaColumnsAmount(config: Config): int =
  var amount = 0
  for column in config.columns:
    if config.hasColumnWorkingArea(column):
      amount += 1
  return amount

proc getColumnMaxWidthPx*(config; path: ColumnPath): float =
  let column = config.getColumn(path)
  let currentWidthPx = config.getColumnWidthPx(column)
  let workingAreaColumnsAmount = config.getWorkingAreaColumnsAmount()
  if config.hasColumnWorkingArea(column) and workingAreaColumnsAmount == 1 and path + 1 <= high(config.columns):
    let nextColumn = config.getColumn(Natural(path + 1))
    result = currentWidthPx + nextColumn.width - float(config.getColumnMinWidthPx(nextColumn))
  else:
    result = float(config.width)
    for c in config.columns:
      if config.hasColumnWorkingArea(c):
        result -= float(config.getColumnMinWidthPx(c))
      elif column != c:
        result -= c.width

proc insertColumn*(config; path: ColumnPath; column: Column) =
  if path > high(config.columns):
    config.columns.add(column)
  else:
    config.columns.insert(@[column], path)

proc resizeColumn*(config; path: ColumnPath; widthPx: float) =
  let column = config.getColumn(path)
  if config.hasColumnWorkingArea(column):
    let workingAreaColumnsAmount = config.getWorkingAreaColumnsAmount()
    if workingAreaColumnsAmount > 1:
      let freeSpace = float(config.width) - config.getFixedColumnsWidth()
      let width = widthPx * 100 / float(freeSpace)
      config.columns[path].width = width
      let widthDiff = (width - column.width) / float(workingAreaColumnsAmount - 1)
      for columnIndex in low(config.columns)..high(config.columns):
        if columnIndex != path:
          config.columns[columnIndex].width -= widthDiff
    else:
      let nextPath = Natural(path + 1)
      let nextColumn = config.getColumn(nextPath)
      let widthDiff = config.getColumnWidthPx(column) - widthPx
      config.resizeColumn(path=nextPath, widthPx=nextColumn.width + widthDiff)
  else:
    config.columns[path].width = widthPx

proc deleteColumn*(config; path: ColumnPath) =
  config.resizeColumn(path=path, widthPx=0)
  config.columns.delete(path)

proc insertRow*(config; path: RowPath; row: Row) =
  if path.index > high(config.columns[path.columnPath].rows):
    config.columns[path.columnPath].rows.add(row)
  else:
    config.columns[path.columnPath].rows.insert(@[row], path.index)

proc resizeRow*(config; path: RowPath; heightPx: float) =
  let row = config.getRow(path)
  let column = config.getColumn(path.columnPath)
  let height = heightPx * 100 / float(config.height)
  var resizeFromIndex: Natural = Natural(0)
  var rowsToResize: int = len(column.rows) - 1
  if path.index < high(column.rows):
    resizeFromIndex = path.index + 1
    rowsToResize -= path.index
  let heightDiff = (height - row.height) / float(rowsToResize)
  config.columns[path.columnPath].rows[path.index].height = height
  for rowIndex in resizeFromIndex..high(column.rows):
    if rowIndex != path.index:
      config.columns[path.columnPath].rows[rowIndex].height -= heightDiff

proc getRowHeightPx(config; row: Row): float =
  row.height * float(config.height) / 100

proc getRowMinHeightPx*(config; row: Row): int =
  result = high(int)
  for panel in row.panels:
    if panel.minHeightPx < result:
      result = panel.minHeightPx

proc getRowMaxHeightPx*(config; path: RowPath): float =
  let column = config.getColumn(path.columnPath)
  var resizeFromIndex =
    if path.index < high(column.rows):
      path.index + 1
    else:
      Natural(0)
  result = float(config.height)
  for rowIndex in resizeFromIndex..high(column.rows):
    if rowIndex != path.index:
      let row = config.getRow((
        columnPath: path.columnPath,
        index: Natural(rowIndex)
      ))
      result -= float(config.getRowMinHeightPx(row))

proc deleteRow*(config; path: RowPath) =
  config.resizeRow(path=path, heightPx=0)
  config.columns[path.columnPath].rows.delete(path.index)
  if len(config.columns[path.columnPath].rows) == 0:
    config.deleteColumn(path.columnPath)

proc insertPanel*(config; path: PanelPath; panel: Panel) =
  if path.index > high(config.columns[path.rowPath.columnPath].rows[path.rowPath.index].panels):
    config.columns[path.rowPath.columnPath].rows[path.rowPath.index].panels.add(panel)
  else:
    config.columns[path.rowPath.columnPath].rows[path.rowPath.index].panels.insert(@[panel], path.index)

proc setActivePanel*(config; path: PanelPath) =
  assert path.index < len(config.columns[path.rowPath.columnPath].rows[path.rowPath.index].panels)
  config.columns[path.rowPath.columnPath].rows[path.rowPath.index].activePanel = path.index

proc deletePanel*(config; path: PanelPath) =
  config.columns[path.rowPath.columnPath].rows[path.rowPath.index].panels.delete(path.index)
  if len(config.columns[path.rowPath.columnPath].rows[path.rowPath.index].panels) == 0:
    config.deleteRow(path.rowPath)
  else:
    config.columns[path.rowPath.columnPath].rows[path.rowPath.index].activePanel = 0

proc movePanel*(config; src: PanelPath; dst: PanelPath) =
  let panel = config.getPanel(src)
  config.insertPanel(path=dst, panel=panel)
  config.deletePanel(path=(
    rowPath: src.rowPath,
    index: if src.rowPath == dst.rowPath and dst.index < src.index: Natural(src.index + 1) else: src.index
  ))

proc movePanel*(config; src: PanelPath, dst: RowPath) =
  let panel = config.getPanel(src)
  let srcRow = config.getRow(src.rowPath)
  let srcRowHeight = config.getRowHeightPx(srcRow)
  let dstColumn = config.getColumn(dst.columnPath)
  let isEmptyColumn = len(dstColumn.rows) == 0
  let isTheSameColumn: bool = src.rowPath.columnPath == dst.columnPath
  if isTheSameColumn and len(srcRow.panels) == 1:
    config.resizeRow(path=src.rowPath, heightPx=0)
  config.insertRow(path=dst, Row(
    panels: @[],
    activePanel: 0,
    height: if isEmptyColumn: 100 else: 0
  ))
  if not isEmptyColumn:
    if not isTheSameColumn or len(srcRow.panels) != 1:
      config.resizeRow(path=dst, heightPx=float(panel.minHeightPx))
    else:
      config.resizeRow(path=dst, heightPx=srcRowHeight)
  let src = (
    rowPath: (
      columnPath: src.rowPath.columnPath,
      index: if isTheSameColumn and src.rowPath.index >= dst.index: Natural(src.rowPath.index + 1) else: src.rowPath.index
    ),
    index: src.index
  )
  config.movePanel(src=src, dst=(
    rowPath: dst,
    index: Natural(0)
  ))

proc movePanel*(config; src: PanelPath, dst: ColumnPath) =
  let panel = config.getPanel(src)
  config.insertColumn(path=dst, Column(
    rows: @[],
    width: float(panel.minWidthPx)
  ))
  let src = (
    rowPath: (
      columnPath: if src.rowPath.columnPath >= dst: Natural(src.rowPath.columnPath + 1) else: src.rowPath.columnPath,
      index: src.rowPath.index
    ),
    index: src.index
  )
  let rowPath = (
    columnPath: dst,
    index: Natural(0)
  )
  config.movePanel(src=src, dst=rowPath)

proc renderRowHeaderItem(config; row: Row; panel: Panel; path: PanelPath): VNode =
  let leftDropPlaceHolderId = cstring"karadock-column-" & &path.rowPath.columnPath & cstring"-row-" & &path.rowPath.index & "-panel-" & &path.index & cstring"-drop-left"
  let rightDropPlaceHolderId = cstring"karadock-column-" & &path.rowPath.columnPath & cstring"-row-" & &path.rowPath.index & "-panel-" & &path.index & cstring"-drop-right"

  proc onClick(ev: Event; n: VNode) =
    if row.activePanel != path.index:
      config.setActivePanel(path=path)
      config.onupdate(config)

  proc onDragStart(ev: Event; n: VNode) =
    draggingPanel = some(path)

  proc onDragEnd(ev: Event; n: VNode) =
    draggingPanel = none(PanelPath)
    dragOverId = nil

  proc onDropPlaceholderDragEnter(dropPlaceholderId: cstring): proc (ev: Event; n: VNode) =
    result = proc (ev: Event; n: VNode) =
      if draggingPanel.isSome:
        ev.preventDefault()
        dragOverId = dropPlaceholderId

  proc onDragOverPlaceholder(ev: Event; n: VNode) =
    if draggingPanel.isSome and dragOverId != nil:
      preventDefault(ev)

  proc onDropPlaceholder(ev: Event; n: VNode) =
    if draggingPanel.isSome and dragOverId != nil:
      preventDefault(ev)
      var dst: PanelPath = path
      if dragOverId == rightDropPlaceHolderId:
        dst = (
          rowPath: path.rowPath,
          index: Natural(path.index + 1)
        )
      config.movePanel(src=draggingPanel.get(), dst=dst)
      draggingPanel = none(PanelPath)
      dragOverId = nil
      config.onupdate(config)

  let style = style(
    (StyleAttr.position, cstring"relative"),
    (StyleAttr.display, cstring"inline-block"),
    (StyleAttr.cursor, cstring"pointer"),
    (StyleAttr.zIndex, cstring"1")
  ).merge(config.panelNameStyle(config=config, path=path));

  var dropPlaceholderLeftStyle = style(
    (StyleAttr.backgroundColor, cstring"transparent"),
    (StyleAttr.position, cstring"absolute"),
    (StyleAttr.left, cstring"0"),
    (StyleAttr.right, cstring"50%"),
    (StyleAttr.top, cstring"0"),
    (StyleAttr.bottom, cstring"0"),
    (StyleAttr.zIndex, cstring"100")
  )

  if dragOverId == leftDropPlaceHolderId:
    dropPlaceholderLeftStyle = dropPlaceholderLeftStyle.merge(
      config.panelNameDropPlaceholderStyle(config=config, path=path)
    )

  var dropPlaceholderRightStyle = style(
    (StyleAttr.backgroundColor, cstring"transparent"),
    (StyleAttr.position, cstring"absolute"),
    (StyleAttr.left, cstring"0"),
    (StyleAttr.right, cstring"0"),
    (StyleAttr.top, cstring"0"),
    (StyleAttr.bottom, cstring"0"),
    (StyleAttr.zIndex, cstring"0")
  )

  if dragOverId == rightDropPlaceHolderId:
    dropPlaceholderRightStyle = dropPlaceholderRightStyle.merge(
      config.panelNameDropPlaceholderStyle(config=config, path=path)
    )

  result = buildHtml(tdiv(style=style(StyleAttr.display, cstring"inline-block"))):
    if draggingPanel.isSome and path.index == high(row.panels):
      tdiv(
        style=dropPlaceholderRightStyle,
        ondragenter=onDropPlaceholderDragEnter(rightDropPlaceHolderId),
        ondragover=onDragOverPlaceholder,
        ondrop=onDropPlaceholder
      )
    tdiv(style=style, draggable=cstring"true", onclick=onClick, ondragstart=onDragStart, ondragend=onDragEnd):
      if draggingPanel.isSome:
        tdiv(
          style=dropPlaceholderLeftStyle,
          ondragenter=onDropPlaceholderDragEnter(leftDropPlaceHolderId),
          ondragover=onDragOverPlaceholder,
          ondrop=onDropPlaceholder
        )
      text panel.name

proc renderRowHeader(config; row: Row; path: RowPath): VNode =
  let style = style(
    (StyleAttr.flex, cstring"0 0 auto"),
    (StyleAttr.position, cstring"relative"),
    (StyleAttr.overflow, cstring"hidden")
  ).merge(config.rowHeaderStyle(config=config, path=path))
  result = buildHtml(tdiv(style=style)):
    for panelIndex in low(row.panels)..high(row.panels):
      let panelPath = (
        rowPath: path,
        index: Natural(panelIndex)
      )
      let panel = config.getPanel(path=panelPath)
      renderRowHeaderItem(config=config, row=row, panel=panel, path=panelPath)

proc renderRow(config; path: RowPath): VNode =
  let column = config.getColumn(path.columnPath)
  let row = config.getRow(path)
  let minHeight = float(config.getRowMinHeightPx(row))
  let maxHeight = float(config.getRowMaxHeightPx(path))
  var height = config.getRowHeightPx(row)
  if height < minHeight:
    height = minHeight
  var resizer: VNode = nil
  let topDropPlaceHolderId = cstring"karadock-column-" & &path.columnPath & cstring"-row-" & &path.index & cstring"-drop-top"
  let bottomDropPlaceHolderId = cstring"karadock-column-" & &path.columnPath & cstring"-row-" & &path.index & cstring"-drop-bottom"

  let style = style(
    (StyleAttr.display, cstring"flex"),
    (StyleAttr.flexDirection, cstring"column"),
    (StyleAttr.alignContent, cstring"stretch"),
    (StyleAttr.position, cstring"relative"),
    (StyleAttr.height, &height & cstring"px")
  ).merge(config.rowStyle(config=config, path=path))

  let bodyStyle = style(
    (StyleAttr.flex, cstring"1 1 0"),
    (StyleAttr.minHeight, cstring"0"),
    (StyleAttr.position, cstring"relative")
  ).merge(config.panelBodyStyle(config=config, path=(rowPath: path, index: row.activePanel)))

  let resizerStyle = style(
    (StyleAttr.position, cstring"absolute"),
    (StyleAttr.left, cstring"0"),
    (StyleAttr.right, cstring"0"),
    (StyleAttr.bottom, cstring"-5px"),
    (StyleAttr.height, cstring"5px"),
    (StyleAttr.zIndex, cstring"100"),
    (StyleAttr.cursor, cstring"row-resize")
  )

  var dropPlaceholderTopStyle = style(
    (StyleAttr.backgroundColor, cstring"transparent"),
    (StyleAttr.position, cstring"absolute"),
    (StyleAttr.left, cstring"0"),
    (StyleAttr.right, cstring"0"),
    (StyleAttr.top, cstring"0"),
    (StyleAttr.bottom, cstring"77%"),
    (StyleAttr.zIndex, cstring"100")
  )

  if dragOverId == topDropPlaceHolderId:
    dropPlaceholderTopStyle = dropPlaceholderTopStyle.merge(
      config.rowDropPlaceholderStyle(config=config, path=path)
    )

  var dropPlaceholderBottomStyle = style(
    (StyleAttr.backgroundColor, cstring"transparent"),
    (StyleAttr.position, cstring"absolute"),
    (StyleAttr.left, cstring"0"),
    (StyleAttr.right, cstring"0"),
    (StyleAttr.top, cstring"77%"),
    (StyleAttr.bottom, cstring"0"),
    (StyleAttr.zIndex, cstring"100")
  )

  if dragOverId == bottomDropPlaceHolderId:
    dropPlaceholderBottomStyle = dropPlaceholderBottomStyle.merge(
      config.rowDropPlaceholderStyle(config=config, path=path)
    )

  var resizerStartY: int = 0

  proc onResizerMouseDown(ev: Event; n: VNode) =
    preventDefault(ev)
    resizerStartY = ev.clientY;

    mousemoveProc = proc (ev: Event) =
      var diff = float(ev.clientY - resizerStartY)
      let newHeight = height + diff
      if newHeight < minHeight:
        diff = minHeight - height
      elif newHeight > maxHeight:
        diff = maxHeight - height
      resizer.dom.applyStyle(resizerStyle.merge(
        style(StyleAttr.bottom, &(-diff) & cstring"px")
      ).merge(config.resizerStyle))

    mouseupProc = proc (ev: Event) =
      var diff = float(ev.clientY - resizerStartY)
      var newHeight = height + diff
      if newHeight < minHeight:
        newHeight = minHeight
      elif newHeight > maxHeight:
        newHeight = maxHeight
      resizer.dom.applyStyle(resizerStyle)
      mousemoveProc = nil
      mouseupProc = nil
      config.resizeRow(path=path, heightPx=newHeight)
      config.onupdate(config)

  proc onDropPlaceholderDragEnter(dropPlaceholderId: cstring): proc (ev: Event; n: VNode) =
    result = proc (ev: Event; n: VNode) =
      if draggingPanel.isSome:
        ev.preventDefault()
        dragOverId = dropPlaceholderId

  proc onDragOverPlaceholder(ev: Event; n: VNode) =
    if draggingPanel.isSome and dragOverId != nil:
      preventDefault(ev)

  proc onDropPlaceholder(ev: Event; n: VNode) =
    if draggingPanel.isSome and dragOverId != nil:
      preventDefault(ev)
      var dst: RowPath = path
      if dragOverId == bottomDropPlaceHolderId:
        dst = (
          columnPath: path.columnPath,
          index: Natural(path.index + 1)
        )
      config.movePanel(src=draggingPanel.get(), dst=dst)
      draggingPanel = none(PanelPath)
      dragOverId = nil
      config.onupdate(config)

  resizer = buildHtml(tdiv(style=resizerStyle, onmousedown=onResizerMouseDown))

  result = buildHtml(tdiv(style=style)):
    if path.index != high(column.rows):
      resizer

    if len(row.panels) > 1 or row.panels.any(proc (panel: Panel): bool = panel.forceDisplayName):
      renderRowHeader(config=config, row=row, path=path)

    tdiv(style=bodyStyle):
      if draggingPanel.isSome:
        tdiv(
          style=dropPlaceholderTopStyle,
          ondragenter=onDropPlaceholderDragEnter(topDropPlaceHolderId),
          ondragover=onDragOverPlaceholder,
          ondrop=onDropPlaceholder
        )
        if path.index == high(column.rows):
          tdiv(
            style=dropPlaceholderBottomStyle,
            ondragenter=onDropPlaceholderDragEnter(bottomDropPlaceHolderId),
            ondragover=onDragOverPlaceholder,
            ondrop=onDropPlaceholder
          )
      row.panels[row.activePanel].body

proc renderColumn(config; path: ColumnPath): VNode =
  let column = config.getColumn(path)
  let minWidth = float(config.getColumnMinWidthPx(column))
  let maxWidth = float(config.getColumnMaxWidthPx(path))
  var width = config.getColumnWidthPx(column)
  if width < minWidth:
    width = minWidth
  var resizer: VNode = nil
  let leftDropPlaceHolderId = cstring"karadock-column-" & &path & cstring"-drop-left"
  let rightDropPlaceHolderId = cstring"karadock-column-" & &path & cstring"-drop-right"

  let columnStyle = style(
    (StyleAttr.display, cstring"inline-block"),
    (StyleAttr.width, &width & "px"),
    (StyleAttr.position, cstring"relative"),
    (StyleAttr.verticalAlign, cstring"top")
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

  var dropPlaceholderLeftStyle = style(
    (StyleAttr.backgroundColor, cstring"transparent"),
    (StyleAttr.position, cstring"absolute"),
    (StyleAttr.left, cstring"0"),
    (StyleAttr.right, cstring"77%"),
    (StyleAttr.top, cstring"0"),
    (StyleAttr.bottom, cstring"0"),
    (StyleAttr.zIndex, cstring"100")
  )

  if dragOverId == leftDropPlaceHolderId:
    dropPlaceholderLeftStyle = dropPlaceholderLeftStyle.merge(
      config.columnDropPlaceholderStyle(config=config, path=path)
    )

  var dropPlaceholderRightStyle = style(
    (StyleAttr.backgroundColor, cstring"transparent"),
    (StyleAttr.position, cstring"absolute"),
    (StyleAttr.left, cstring"77%"),
    (StyleAttr.right, cstring"0"),
    (StyleAttr.top, cstring"0"),
    (StyleAttr.bottom, cstring"0"),
    (StyleAttr.zIndex, cstring"100")
  )

  if dragOverId == rightDropPlaceHolderId:
    dropPlaceholderRightStyle = dropPlaceholderRightStyle.merge(
      config.columnDropPlaceholderStyle(config=config, path=path)
    )

  var resizerStartX: int = 0

  proc onResizerMouseDown(ev: Event; n: VNode) =
    preventDefault(ev)
    resizerStartX = ev.clientX;

    mousemoveProc = proc (ev: Event) =
      var diff = float(ev.clientX - resizerStartX)
      let newWidth = width + diff
      if newWidth < minWidth:
        diff = minWidth - width
      elif newWidth > maxWidth:
        diff = maxWidth - width
      resizer.dom.applyStyle(resizerStyle.merge(
        style(StyleAttr.right, &(-diff) & cstring"px")
      ).merge(config.resizerStyle))

    mouseupProc = proc (ev: Event) =
      let diff = float(ev.clientX - resizerStartX)
      var newWidth = width + diff
      if newWidth < minWidth:
        newWidth = minWidth
      elif newWidth > maxWidth:
        newWidth = maxWidth
      resizer.dom.applyStyle(resizerStyle)
      mousemoveProc = nil
      mouseupProc = nil
      config.resizeColumn(path=path, widthPx=newWidth)
      config.onupdate(config)

  proc onDropPlaceholderDragEnter(dropPlaceholderId: cstring): proc (ev: Event; n: VNode) =
    result = proc (ev: Event; n: VNode) =
      if draggingPanel.isSome:
        ev.preventDefault()
        dragOverId = dropPlaceholderId

  proc onDragOverPlaceholder(ev: Event; n: VNode) =
    if draggingPanel.isSome and dragOverId != nil:
      preventDefault(ev)

  proc onDropPlaceholder(ev: Event; n: VNode) =
    if draggingPanel.isSome and dragOverId != nil:
      preventDefault(ev)
      var dst: ColumnPath = path
      if dragOverId == rightDropPlaceHolderId:
        dst = Natural(path + 1)
      config.movePanel(src=draggingPanel.get(), dst=dst)
      draggingPanel = none(PanelPath)
      dragOverId = nil
      config.onupdate(config)

  resizer = buildHtml(tdiv(style=resizerStyle, onmousedown=onResizerMouseDown))

  result = buildHtml(tdiv(style=columnStyle)):
    if path != high(config.columns):
      resizer

    if draggingPanel.isSome:
      tdiv(
        style=dropPlaceholderLeftStyle,
        ondragenter=onDropPlaceholderDragEnter(leftDropPlaceHolderId),
        ondragover=onDragOverPlaceholder,
        ondrop=onDropPlaceholder
      )
      if path == high(config.columns):
        tdiv(
          style=dropPlaceholderRightStyle,
          ondragenter=onDropPlaceholderDragEnter(rightDropPlaceHolderId),
          ondragover=onDragOverPlaceholder,
          ondrop=onDropPlaceholder
        )

    for rowIndex in low(column.rows)..high(column.rows):
      renderRow(config=config, path=(
        columnPath: path,
        index: Natural(rowIndex)
      ))

proc karaDock*(config): VNode =
  let style = style(
    (StyleAttr.width, &config.width & cstring"px"),
    (StyleAttr.height, &config.height & cstring"px"),
    (StyleAttr.whiteSpace, cstring"nowrap"),
    (StyleAttr.overflow, cstring"auto")
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
