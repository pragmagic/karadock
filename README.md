# KaraDock

Dock layout engine based on Karax framework.

Example:

```nim
const border = "4px solid black"
const dropPlaceholderColor = "rgba(26, 135, 230, 0.5)"
const bodyColor = "rgb(78, 79, 81)"
const PanelAName = "Panel A"
const PanelBName = "Panel B"
const PanelCName = "Panel C"
const PanelDName = "Panel D"
const PanelEName = "Panel E"

var config = Config(
  columnStyle: proc(config; path: ColumnPath): VStyle =
    style(borderLeft ~ (if path != 0: border else: "0")),

  columnDropPlaceholderStyle: proc(config; path: ColumnPath): VStyle =
    style(backgroundColor ~ dropPlaceholderColor),

  rowStyle: proc(config; path: RowPath): VStyle =
    style(
      borderTop ~ (if path.index != 0: border else: "0"),
      backgroundColor ~ bodyColor
    ),

  rowHeaderStyle: proc(config; path: RowPath): VStyle =
    style(backgroundColor ~ "black"),

  rowDropPlaceholderStyle: proc(config; path: RowPath): VStyle =
    style(backgroundColor ~ dropPlaceholderColor),

  panelNameStyle: proc(config; path: PanelPath): VStyle =
    let row = getRow(config=config, path=path.rowPath)
    let isActive = row.activePanel == path.index
    result = style(
      height ~ "26px",
      lineHeight ~ "26px",
      paddingLeft ~ "15px",
      paddingRight ~ "15px",
      fontWeight ~ "500",
      backgroundColor ~ (if isActive: bodyColor else: "black"),
      color ~ (if isActive: "#c7c7c8" else: "#666666")
    ),

  panelNameDropPlaceholderStyle: proc(config; path: PanelPath): VStyle =
    style(backgroundColor ~ dropPlaceholderColor),

  panelBodyStyle: proc(config; path: PanelPath): VStyle =
    style(padding ~ "5px"),

  resizerStyle: style(backgroundColor ~ "rgba(255, 255, 255, 0.5)"),

  onupdate: proc(configUpd: Config) =
    #e.g. save configUpd.columns to LocalStorage
    redraw(),

  width: window.innerWidth,
  height: window.innerHeight,

  columns: @[
    Column(
      width: 250,
      rows: @[
        Row(
          height: 60,
          activePanel: 0,
          panels: @[
            Panel(
              name: PanelAName,
              isWorkingArea: false,
              forceDisplayName: true,
              minWidthPx: 250,
              minHeightPx: 200,
              body: buildHtml(text PanelAName)
            )
          ]
        ),
        Row(
          height: 40,
          activePanel: 1,
          panels: @[
            Panel(
              name: PanelBName,
              isWorkingArea: false,
              forceDisplayName: true,
              minWidthPx: 250,
              minHeightPx: 200,
              body: buildHtml(text PanelBName)
            ),
            Panel(
              name: PanelCName,
              isWorkingArea: false,
              forceDisplayName: true,
              minWidthPx: 250,
              minHeightPx: 200,
              body: buildHtml(text PanelCName)
            )
          ]
        )
      ]
    ),

    Column(
      width: 100,
      rows: @[
        Row(
          height: 100,
          activePanel: 0,
          panels: @[
            Panel(
              name: PanelDName,
              isWorkingArea: true,
              forceDisplayName: false,
              minWidthPx: 400,
              minHeightPx: 300,
              body: buildHtml(text PanelDName)
            )
          ]
        )
      ]
    ),

    Column(
      width: 200,
      rows: @[
        Row(
          height: 100,
          activePanel: 0,
          panels: @[
            Panel(
              name: PanelEName,
              isWorkingArea: false,
              forceDisplayName: true,
              minWidthPx: 200,
              minHeightPx: 300,
              body: buildHtml(text PanelEName)
            )
          ]
        )
      ]
    )
  ]
)

window.addEventListener(cstring"resize", proc(event) =
  config.width = window.innerWidth
  config.height = window.innerHeight
  redraw()
)

proc createDom(): VNode =
  let style = style(
    color ~ "white",
    fontSize ~ "16px"
  )

  result = buildHtml(tdiv(style=style)):
    karaDock(config)

setRenderer createDom
```

![Example](/example-complex.gif?raw=true "Example")

To run the example above:

```
  nimble install # For first time
```

```
  cd examples/
  nim js complex.nim
  open complex.html
```

## TODO

* Use UUID instead of numeric indexes as panel/row/column paths.
* Automatically collapse/expand rows based on current available `config.height` and sum of `Panel.minHeightPx`.
* Automatically wrap right columns to the left based on current available `config.width` and `Column.width`.

## License
This library is licensed under the MIT license.
Read [LICENSE](https://github.com/pragmagic/karadoc/blob/master/LICENSE) file for details.

Copyright (c) 2017 Pragmagic, Inc.
