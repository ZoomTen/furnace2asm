import ../res/resources
import wNim/[wApp, wFrame]

import appFrame

when isMainModule:
  let
    app = App(wSystemDpiAware)
    app_frm = MyAppFrame()
  app_frm.show()
  app.mainLoop()