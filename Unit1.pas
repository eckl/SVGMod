Unit Unit1;

Interface

Uses
  Winapi.Windows,
  Winapi.Messages,
  System.SysUtils,
  System.Variants,
  System.StrUtils,
  System.RegularExpressions,
  System.Classes,
  System.Diagnostics,
  Vcl.Graphics,
  Vcl.Controls,
  Vcl.Forms,
  Vcl.Dialogs,
  Vcl.StdCtrls,
  Vcl.Menus,
  Vcl.FileCtrl,
  qstring,
  qrbtree,
  qxml;

Type
  TForm1 = Class(TForm)
    Memo1: TMemo;
    MainMenu1: TMainMenu;
    Modify: TMenuItem;
    Procedure ModifyClick(Sender: TObject);

  Private
    Procedure ProcessSVGFile(Const AFileName: String);
    Procedure AppendTextNode(AParent: TQXMLNode; Const AX, AY, ADirection, AText: String);

  Public
    { Public declarations }
  End;

Var
  Form1: TForm1;

Implementation

{$R *.dfm}

Const
  PATTERN_EXCLUDE_DEVICES = '手车|刀闸|地刀|开关';
  PATTERN_KEEP_TEXT = '变|运维|';
  SVG_FONT_FAMILY = 'SimSun';
  SVG_FONT_SIZE = '20';
  SVG_FILL_COLOR = 'rgb(0,255,0)';
  SVG_STROKE_COLOR = 'rgb(255,255,254)';

Procedure TForm1.AppendTextNode(AParent: TQXMLNode; Const AX, AY, ADirection, AText: String);
Var
  NewNode: TQXMLNode;
Begin
  If Not Assigned(AParent) Then Exit;
  NewNode := AParent.Add('text');
  NewNode.Attrs.Add('x', AX);
  NewNode.Attrs.Add('y', AY);
  NewNode.Attrs.Add('font-size', SVG_FONT_SIZE);
  NewNode.Attrs.Add('font-width', SVG_FONT_SIZE);
  NewNode.Attrs.Add('font-height', SVG_FONT_SIZE);
  NewNode.Attrs.Add('font-family', SVG_FONT_FAMILY);
  NewNode.Attrs.Add('fill', SVG_FILL_COLOR);
  NewNode.Attrs.Add('stroke', SVG_STROKE_COLOR);
  NewNode.Attrs.Add('writing-mode', ADirection);
  NewNode.Attrs.Add('Plane', '0');
  NewNode.Attrs.Add('AFMask', '39039');
  NewNode.Attrs.Add('xml:space', 'preserve');
  NewNode.Text := AText;
End;

Procedure TForm1.ProcessSVGFile(Const AFileName: String);
  Function FindNodeByAttr(ANode: TQXMLNode; Const ATag, AAttr, AValue: String): TQXMLNode;
  Var
    J: Integer;
  Begin
    Result := Nil;
    If Not Assigned(ANode) Then Exit;
    If (ANode.Name = ATag) And (ANode.Attrs.ValueByName(AAttr) = AValue) Then Exit(ANode);
    For J := 0 To ANode.Count - 1 Do Begin
      Result := FindNodeByAttr(ANode[J], ATag, AAttr, AValue);
      If Assigned(Result) Then Exit;
    End;
  End;

Var
  I: Integer;
  svg: TQXMLNode;
  SymbolTerminal: TQXMLNode;
  HeadLayer: TQXMLNode;
  TextLayer: TQXMLNode;
  MeasLayer: TQXMLNode;
  OtherLayer: TQXMLNode;
  MeasItem, TxtNode: TQXMLNode;
  Attr: TQXMLAttr;
  DeviceName: String;
  DeviceNo: String;
  rec: TArray<String>;
  x, y: String;
  height, width: String;
Begin
  svg := TQXMLNode.Create;
  Try
    svg.LoadFromFile(AFileName);
    If svg.Count = 0 Then Exit;
    // --- Step 1: 修正终端符号的对齐基准点 ---
    SymbolTerminal := FindNodeByAttr(svg[0], 'symbol', 'id', 'terminal');
    If Assigned(SymbolTerminal) Then Begin
      For I := 0 To SymbolTerminal.Attrs.Count - 1 Do SymbolTerminal.Attrs[I].Value := ReplaceText(SymbolTerminal.Attrs[I].Value, 'xMidYMid', 'xMinYMin');
    End;
    // --- Step 2: 根据 Head_Layer 的 rect 尺寸重写 viewBox ---
    HeadLayer := FindNodeByAttr(svg[0], 'g', 'id', 'Head_Layer');
    If Assigned(HeadLayer) Then Begin
      MeasItem := HeadLayer.ItemByName('rect');
      If Assigned(MeasItem) And Assigned(MeasItem.Attrs) Then Begin
        height := MeasItem.Attrs.ValueByName('height');
        width := MeasItem.Attrs.ValueByName('width');
        Attr := svg[0].Attrs.ItemByName('viewBox');
        If Assigned(Attr) Then Attr.Value := Format('0 0 %s %s', [width, height])
        Else svg[0].Attrs.Add('viewBox', Format('0 0 %s %s', [width, height]));
      End;
    End;
    // --- Step 2.5: 删除 Other_Layer 下的 img 和 a 节点 ---
    OtherLayer := FindNodeByAttr(svg[0], 'g', 'id', 'Other_Layer');
    If Assigned(OtherLayer) Then Begin
      For I := OtherLayer.Count - 1 Downto 0 Do Begin
        If (OtherLayer.Items[I].Name = 'image') Or (OtherLayer.Items[I].Name = 'a') Then OtherLayer.Delete(I);
      End;
    End;
    // --- Step 3: 过滤 Text_Layer，仅保留包含"变"或"运维"的行 ---
    TextLayer := FindNodeByAttr(svg[0], 'g', 'id', 'Text_Layer');
    If Assigned(TextLayer) Then Begin
      For I := TextLayer.Count - 1 Downto 0 Do Begin
        If (TextLayer.Items[I].Name = 'text') And (Not TRegEx.IsMatch(TextLayer.Items[I].Text, PATTERN_KEEP_TEXT)) Then TextLayer.Delete(I);
      End;
    End;
    // --- Step 4 & 5: 提取设备名称并生成 SVG 注记标签，然后清除占位符 ---
    MeasLayer := FindNodeByAttr(svg[0], 'g', 'id', 'MeasurementValue_Layer');
    If Assigned(MeasLayer) Then Begin
      For I := 0 To MeasLayer.Count - 1 Do Begin
        MeasItem := MeasLayer.Items[I];
        TxtNode := MeasItem.ItemByName('text');
        If Assigned(TxtNode) Then Begin
          If TxtNode.Text = 'ssss' Then Begin
            x := TxtNode.Attrs.ValueByName('x');
            y := TxtNode.Attrs.ValueByName('y');
            // 从 CIM 元数据中提取设备全名
            If Assigned(MeasItem.ItemByName('metadata')) And Assigned(MeasItem.ItemByName('metadata').ItemByName('cge:Meas_Ref')) Then Begin
              DeviceName := MeasItem.ItemByName('metadata').ItemByName('cge:Meas_Ref').Attrs.ValueByName('ObjectName');
              If DeviceName <> '' Then Begin
                rec := DeviceName.Split(['.']);
                DeviceName := ReplaceText(rec[High(rec)], ':other', '');
                If Not TRegEx.IsMatch(DeviceName, PATTERN_EXCLUDE_DEVICES) Then Begin
                  If TRegEx.IsMatch(DeviceName, 'kV') Then Begin
                    // 电压等级标签：水平显示，微上移
                    AppendTextNode(svg[0], x, IntToStr(StrToIntDef(y, 0) - 3), 'lr', DeviceName);
                  End Else Begin
                    // 设备标签：编号水平 + 名称垂直
                    DeviceNo := TRegEx.Match(DeviceName, '[0-9]{3,5}').Value;
                    AppendTextNode(svg[0], x, y, 'lr', DeviceNo);
                    DeviceName := ReplaceText(DeviceName, '_', '');
                    DeviceName := ReplaceText(DeviceName, DeviceNo, '');
                    AppendTextNode(svg[0], IntToStr(StrToIntDef(x, 0) + 15), IntToStr(StrToIntDef(y, 0) + 10), 'tb', DeviceName);
                  End;
                End;
              End;
            End;
          End;
          // 清除占位符
          TxtNode.Text := ReplaceText(TxtNode.Text, 'ssss', '');
          TxtNode.Text := ReplaceText(TxtNode.Text, '-00.00', '');
          TxtNode.Text := ReplaceText(TxtNode.Text, '-000', '');
        End;
      End;
    End;
    // 保存文件（直接通过 QXML 的机制写入）
    svg.SaveToFile(AFileName);
  Finally svg.Free;
  End;
End;

Procedure TForm1.ModifyClick(Sender: TObject);
Var
  I: Integer;
  Path: String;
  Found: Integer;
  SearchRec: TSearchRec;
  FileList: TStringList;
  Stopwatch: TStopwatch;
Begin
  Path := 'c:\zzz\svg\'; // 默认路径，可以修改为 ExtractFilePath(Application.ExeName)
  // 增加目录选择对话框，以防固定路径不存在
  If Not SelectDirectory('选择 SVG 文件所在目录', '', Path) Then Exit;
  Path := IncludeTrailingPathDelimiter(Path);
  Memo1.Lines.Clear;
  Memo1.Lines.Add('开始扫描目录: ' + Path);
  Application.ProcessMessages;
  FileList := TStringList.Create;
  Try
    Found := FindFirst(Path + '*.svg', faNormal, SearchRec);
    Try
      While Found = 0 Do Begin
        FileList.Add(Path + SearchRec.Name);
        Found := FindNext(SearchRec);
      End;
    Finally FindClose(SearchRec);
    End;
    If FileList.Count = 0 Then Begin
      Memo1.Lines.Add('该目录下未找到 SVG 文件。');
      Exit;
    End;
    FileList.Sort;
    Memo1.Lines.Add(Format('找到 %d 个文件，正在处理...', [FileList.Count]));
    Application.ProcessMessages;
    Stopwatch := TStopwatch.StartNew;
    For I := 0 To FileList.Count - 1 Do Begin
      Try
        ProcessSVGFile(FileList[I]);
        Memo1.Lines.Add(Format('[%d/%d] %s', [I + 1, FileList.Count, ExtractFileName(FileList[I])]));
      Except
        On E: Exception Do Memo1.Lines.Add(Format('[%d/%d] 处理失败 %s: %s', [I + 1, FileList.Count, ExtractFileName(FileList[I]), E.Message]));
      End;
      // 保持界面响应
      If I Mod 10 = 0 Then Application.ProcessMessages;
    End;
    Stopwatch.Stop;
    Memo1.Lines.Add(Format('Complete! 共处理 %d 个文件，耗时 %.2f 秒。', [FileList.Count, Stopwatch.Elapsed.TotalSeconds]));
  Finally FileList.Free;
  End;
End;

End.

