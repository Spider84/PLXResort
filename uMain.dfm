object fmMain: TfmMain
  Left = 600
  Top = 275
  Width = 351
  Height = 359
  BorderIcons = [biSystemMenu, biMinimize]
  Caption = 'PLX Reorder'
  Color = clBtnFace
  Constraints.MinHeight = 320
  Constraints.MinWidth = 340
  Font.Charset = DEFAULT_CHARSET
  Font.Color = clWindowText
  Font.Height = -11
  Font.Name = 'MS Sans Serif'
  Font.Style = []
  OldCreateOrder = False
  Position = poScreenCenter
  OnCreate = FormCreate
  OnDestroy = FormDestroy
  PixelsPerInch = 96
  TextHeight = 13
  object lblFromPORT: TTntLabel
    Left = 0
    Top = 8
    Width = 57
    Height = 13
    Caption = 'Sensor port:'
  end
  object lblEmulatePort: TTntLabel
    Left = 160
    Top = 8
    Width = 74
    Height = 13
    Caption = 'Emulate to port:'
  end
  object lvSensors: TTntListView
    Left = 0
    Top = 32
    Width = 335
    Height = 270
    Align = alCustom
    Anchors = [akLeft, akTop, akRight, akBottom]
    Checkboxes = True
    Columns = <
      item
        Caption = 'ID'
        Width = 30
      end
      item
        AutoSize = True
        Caption = 'Sensor'
      end
      item
        Alignment = taRightJustify
        Caption = 'Cnt'
        Width = 30
      end
      item
        Alignment = taRightJustify
        Caption = 'Raw'
      end
      item
        Alignment = taRightJustify
        Caption = 'Value'
        Width = 60
      end>
    FullDrag = True
    ReadOnly = True
    RowSelect = True
    TabOrder = 2
    ViewStyle = vsReport
    OnCompare = lvSensorsCompare
    OnSelectItem = lvSensorsSelectItem
  end
  object cbbFromPORT: TTntComboBox
    Left = 60
    Top = 6
    Width = 93
    Height = 21
    ItemHeight = 13
    TabOrder = 0
    Text = 'COM40'
    OnChange = cbbFromPORTChange
  end
  object cbbEmulatePORT: TTntComboBox
    Left = 238
    Top = 6
    Width = 93
    Height = 21
    ItemHeight = 13
    TabOrder = 1
    Text = 'COM30'
    OnChange = cbbEmulatePORTChange
  end
  object tntstsbr1: TTntStatusBar
    Left = 0
    Top = 302
    Width = 335
    Height = 19
    Panels = <
      item
        Style = psOwnerDraw
        Text = '00'
        Width = 40
      end
      item
        Width = 50
      end>
    OnDrawPanel = tntstsbr1DrawPanel
  end
  object tmrSend: TTimer
    Enabled = False
    Interval = 100
    OnTimer = tmrSendTimer
    Left = 8
    Top = 56
  end
  object tntpmn1: TTntPopupMenu
    OnPopup = tntpmn1Popup
    Left = 40
    Top = 56
    object tntmntmDisable: TTntMenuItem
      Caption = 'Disable'
      Default = True
      OnClick = tntmntmDisableClick
    end
    object tntmntmN1: TTntMenuItem
      Caption = '-'
    end
  end
  object tmrLedOff: TTimer
    Enabled = False
    Interval = 50
    OnTimer = tmrLedOffTimer
    Left = 8
    Top = 88
  end
  object tmrRedLedOff: TTimer
    Enabled = False
    Interval = 40
    OnTimer = tmrRedLedOffTimer
    Left = 40
    Top = 88
  end
  object tmr1: TTimer
    OnTimer = tmr1Timer
    Left = 160
    Top = 80
  end
  object xpmnfst1: TXPManifest
    Left = 72
    Top = 56
  end
  object jvlgfl1: TJvLogFile
    FileName = 'plx.log'
    AutoSave = True
    DefaultSeverity = lesInformation
    Left = 72
    Top = 88
  end
  object jvprgstrystrg1: TJvAppRegistryStorage
    StorageOptions.BooleanStringTrueValues = 'TRUE, YES, Y'
    StorageOptions.BooleanStringFalseValues = 'FALSE, NO, N'
    StorageOptions.BooleanAsString = False
    StorageOptions.DateTimeAsString = False
    Root = 'Software\Spider\PLXResort'
    SubStorages = <>
    Left = 72
    Top = 120
  end
  object jvfrmstrg1: TJvFormStorage
    AppStorage = jvprgstrystrg1
    AppStoragePath = '%FORM_NAME%\'
    Options = [fpSize, fpLocation, fpActiveControl]
    StoredValues = <>
    Left = 72
    Top = 152
  end
end
