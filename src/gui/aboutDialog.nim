import
  wNim/[
    wApp, wFrame, wMacros, wWindow, wPanel, wBitmap, wStaticBitmap, wStaticBox, wButton,
    wStaticText, wHyperlinkCtrl, wFont,
  ]
import strformat
import ../versionInfo

type wAboutDialog* = ref object of wFrame
  canvas: wPanel
  hdrControl: wStaticBitmap
  cvsContainer: wPanel

  frmVersionInfo: wStaticBox
  frmGreetz: wStaticBox

  btnOk: wButton

const
  hdrImage = staticRead("images/aboutHeader.png")
  hdrSide = staticRead("images/headerSideImg.png")

wClass(wAboutDialog of wFrame):
  proc init(self: wAboutDialog, owner: wWindow) =
    wFrame(self).init(
      title = "About Furnace2Asm",
      owner = owner,
      style = wCaption or wDefaultDialogStyle,
      size = (400, 400),
    )

    self.canvas = self.Panel()

    let canvas = self.canvas
    self.autolayout """
        HV:|[canvas]|
        """

    self.hdrControl = self.canvas.StaticBitmap(bitmap = Bitmap(hdrImage))

    self.cvsContainer = self.canvas.Panel()

    let
      hdrControl = self.hdrControl
      cvsContainer = self.cvsContainer

    self.canvas.autolayout """
        H:|[hdrControl]|
        H:|[cvsContainer]
        V:|[hdrControl(100)][cvsContainer]|
        """

    self.frmVersionInfo = self.cvsContainer.StaticBox(label = "Version")

    self.frmGreetz = self.cvsContainer.StaticBox(label = "Greetz to")

    self.btnOk = self.cvsContainer.Button(label = "Nice >:]")

    let
      verinfo = self.frmVersionInfo
      greetz = self.frmGreetz
      greetzCol1 = greetz.Panel()
      greetzCol2 = greetz.Panel()
      ok = self.btnOk
      sideImg = self.cvsContainer.StaticBitmap(bitmap = Bitmap(hdrSide))

    self.cvsContainer.autolayout """
            spacing: 10
            H:|-[verinfo]-|
            H:|-[greetz]-[sideImg(80)]-|
            H:|-24-[ok]-24-|
            V:|[verinfo(greetz/3)]-[greetz]-[ok(==32)]|
            V:|-[verinfo]-[sideImg(80)]-[ok]-|
        """

    greetz.autolayout """
        spacing: 10
        H:|[greetzCol1(greetzCol2)][greetzCol2]|
        V:|[greetzCol1]|
        V:|[greetzCol2]|
        """

    let
      lblGreetz1 = greetzCol1.StaticText(label = "TastySnax12")
      lblGreetz2 = greetzCol1.StaticText(label = "Blue Mario")
      lblGreetz3 = greetzCol1.StaticText(label = "tildearrow")
      lblGreetz4 = greetzCol1.StaticText(label = "wNim Project")
      lblGreetz5 = greetzCol2.StaticText(label = "VisualPharm")
      lblGreetz6 = greetzCol2.StaticText(label = "vbcorner.net")
      lblGreetz7 = greetzCol2.StaticText(label = "pret")
      lblGreetz8 = greetzCol2.StaticText(label = "RainbowDevs")
      lblGreetzEnd = greetzCol2.Panel() # workaround

    greetzCol1.autolayout """
            spacing: 10
            H:|[lblGreetz1]|
            H:|[lblGreetz2]|
            H:|[lblGreetz3]|
            H:|[lblGreetz4]|
            V:|[lblGreetz1(14)]-[lblGreetz2(14)]-[lblGreetz3(14)]-[lblGreetz4(14)]~|
        """

    greetzCol2.autolayout """
            spacing: 10
            H:|[lblGreetz5]|
            H:|[lblGreetz6]|
            H:|[lblGreetz7]|
            H:|[lblGreetz8]|
            V:|[lblGreetz5(14)]-[lblGreetz6(14)]-[lblGreetz7(14)]-[lblGreetz8(14)][lblGreetzEnd]|
        """

    let verlabel = self.frmVersionInfo.StaticText(
      label = fmt"{VersionMajor}.{VersionMinor} build {VersionBuild}",
      style = wAlignCenter or wAlignMiddle,
    )

    verlabel.setFont(
      Font(faceName = "tahoma", pointSize = 12.0, weight = wFontWeightBold)
    )

    self.frmVersionInfo.autolayout """
        H:|[verlabel]|
        V:|[verlabel]|
        """

    self.btnOk.wEvent_Button do():
      self.close()

    self.wEvent_Close do():
      self.endModal()

    self.showModal()
    self.delete()

export AboutDialog
