unit Unit1;

interface

uses
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
  Vcl.FileCtrl;

type
  TForm1 = class(TForm)
    Memo1: TMemo;
    MainMenu1: TMainMenu;
    Modify: TMenuItem;
    procedure ModifyClick(Sender: TObject);
  private
    procedure ProcessSVGFile(const AFileName: string);
    function BuildTextElement(const AX, AY, ADirection, AText: string): string;
  public
    { Public declarations }
  end;

var
  Form1: TForm1;

implementation

{$R *.dfm}

uses
  qstring,
  qrbtree,
  qxml;

const
  /// 过滤排除的设备类型（手车、刀闸、地刀、开关）
  PATTERN_EXCLUDE_DEVICES = '手车|刀闸|地刀|开关';
  /// 文本图层中需保留的关键字（变、运维）
  PATTERN_KEEP_TEXT       = '变|运维|';

  // SVG 文本元素渲染属性
  SVG_FONT_FAMILY  = 'SimSun';
  SVG_FONT_SIZE    = '20';
  SVG_FILL_COLOR   = 'rgb(0,255,0)';
  SVG_STROKE_COLOR = 'rgb(255,255,254)';

type
  TStringListHelper = class helper for TStrings
  public
    // CaseSensitive: 是否区分大小写（默认 False，忽略大小写）
    function IndexOfPrefix(const APrefix: string; CaseSensitive: Boolean = False): Integer;
  end;

function TStringListHelper.IndexOfPrefix(const APrefix: string; CaseSensitive: Boolean): Integer;
var
  I: Integer;
begin
  Result := -1;
  for I := 0 to Count - 1 do
  begin
    if CaseSensitive then
    begin
      if StartsStr(APrefix, Strings[I]) then
        Exit(I);
    end
    else
    begin
      if StartsText(APrefix, Strings[I]) then
        Exit(I);
    end;
  end;
end;

function TForm1.BuildTextElement(const AX, AY, ADirection, AText: string): string;
begin
  Result := Format(
    '<text x="%s" y="%s" font-size="%s" font-width="%s" font-height="%s" ' +
    'font-family="%s" fill="%s" stroke="%s" writing-mode="%s" ' +
    'Plane="0" AFMask="39039" xml:space="preserve">%s</text>',
    [AX, AY, SVG_FONT_SIZE, SVG_FONT_SIZE, SVG_FONT_SIZE,
     SVG_FONT_FAMILY, SVG_FILL_COLOR, SVG_STROKE_COLOR, ADirection, AText]);
end;

procedure TForm1.ProcessSVGFile(const AFileName: string);
var
  I, idx            : Integer;
  svg               : TQXMLNode;
  MeasLayer         : TQXMLNode;
  MeasItem, TxtNode : TQXMLNode;
  Attrs             : TQXMLAttrs;
  DeviceName        : string;
  DeviceNo          : string;
  rec               : TArray<string>;
  x, y              : string;
  height, width     : string;
  svgFile           : TStringList;
begin
  svg := TQXMLNode.Create;
  svgFile := TStringList.Create;
  try
    svg.LoadFromFile(AFileName);
    svgFile.LoadFromFile(AFileName, TEncoding.UTF8);

    // --- Step 1: 修正终端符号的对齐基准点 ---
    idx := svgFile.IndexOfPrefix('<symbol id="terminal"');
    if idx >= 0 then
      svgFile[idx] := ReplaceText(svgFile[idx], 'xMidYMid', 'xMinYMin');

    // --- Step 2: 根据 Head_Layer 的 rect 尺寸重写 viewBox ---
    if svg.Count > 0 then
    begin
      Attrs := svg[0].ItemWithAttrValue('g', 'id', 'Head_Layer').ItemByName('rect').Attrs;
      if Assigned(Attrs) then
      begin
        height := Attrs.ValueByName('height');
        width := Attrs.ValueByName('width');

        idx := svgFile.IndexOfPrefix('<svg');
        if idx >= 0 then
          svgFile[idx] := TRegEx.Replace(
            svgFile[idx],
            'viewBox="[^"]*"',
            Format('viewBox="0,0,%s,%s"', [width, height]),
            [roIgnoreCase]);
      end;
    end;

    // --- Step 3: 过滤 Text_Layer，仅保留包含"变"或"运维"的行 ---
    idx := svgFile.IndexOf('<g id="Text_Layer">');
    if idx >= 0 then
    begin
      Inc(idx); // 跳过开标签行
      while idx < svgFile.Count do
      begin
        if svgFile[idx] = '</g>' then
          Break;
        if not TRegEx.IsMatch(svgFile[idx], PATTERN_KEEP_TEXT) then
          svgFile.Delete(idx)
        else
          Inc(idx);
      end;
    end;

    // --- Step 4: 清除 MeasurementValue_Layer 中的占位符文本 ---
    idx := svgFile.IndexOf('<g id="MeasurementValue_Layer">');
    if idx >= 0 then
    begin
      // 原始代码是直接遍历到末尾，因为占位符 ssss 等具唯一性
      for I := idx to svgFile.Count - 1 do
      begin
        svgFile[I] := ReplaceText(svgFile[I], 'ssss', '');
        svgFile[I] := ReplaceText(svgFile[I], '-00.00', '');
        svgFile[I] := ReplaceText(svgFile[I], '-000', '');
      end;
    end;

    // --- Step 5: 提取设备名称并生成 SVG 注记标签 ---
    if svg.Count > 0 then
    begin
      MeasLayer := svg[0].ItemWithAttrValue('g', 'id', 'MeasurementValue_Layer');
      if Assigned(MeasLayer) then
      begin
        // 动态计算插入点：寻找 </svg> 标签，如果找不到，就放末尾
        idx := svgFile.Count - 1;
        while (idx > 0) and (not StartsText('</svg', Trim(svgFile[idx]))) do
          Dec(idx);
        if idx <= 0 then idx := svgFile.Count - 1;

        for I := 0 to MeasLayer.Count - 1 do
        begin
          MeasItem := MeasLayer.Items[I];
          TxtNode := MeasItem.ItemByName('text');

          if (not Assigned(TxtNode)) or (TxtNode.Text <> 'ssss') then
            Continue;

          x := TxtNode.Attrs.ValueByName('x');
          y := TxtNode.Attrs.ValueByName('y');

          // 从 CIM 元数据中提取设备全名
          if Assigned(MeasItem.ItemByName('metadata')) and
             Assigned(MeasItem.ItemByName('metadata').ItemByName('cge:Meas_Ref')) then
          begin
            DeviceName := MeasItem.ItemByName('metadata')
                                   .ItemByName('cge:Meas_Ref')
                                   .Attrs.ValueByName('ObjectName');
            if DeviceName = '' then
              Continue;

            // 取最后一段，剥离 :other 后缀
            rec := DeviceName.Split(['.']);
            DeviceName := ReplaceText(rec[High(rec)], ':other', '');

            // 跳过不需要标注的常规开关设备
            if TRegEx.IsMatch(DeviceName, PATTERN_EXCLUDE_DEVICES) then
              Continue;

            if TRegEx.IsMatch(DeviceName, 'kV') then
            begin
              // 电压等级标签：水平显示，微上移
              svgFile.Insert(idx,
                BuildTextElement(x, IntToStr(StrToIntDef(y, 0) - 3), 'lr', DeviceName));
            end
            else
            begin
              // 设备标签：编号水平 + 名称垂直
              DeviceNo := TRegEx.Match(DeviceName, '[0-9]{3,5}').Value;
              // 插入编号 (因为使用 Insert，后插入的会在前面，所以先插入名称再插入编号也可，这里保持顺序)
              svgFile.Insert(idx,
                BuildTextElement(x, y, 'lr', DeviceNo));

              DeviceName := ReplaceText(DeviceName, '_', '');
              DeviceName := ReplaceText(DeviceName, DeviceNo, '');
              svgFile.Insert(idx,
                BuildTextElement(
                  IntToStr(StrToIntDef(x, 0) + 15),
                  IntToStr(StrToIntDef(y, 0) + 10),
                  'tb', DeviceName));
            end;
          end;
        end;
      end;
    end;

    svgFile.SaveToFile(AFileName, TEncoding.UTF8);
  finally
    svgFile.Free;
    svg.Free;
  end;
end;

procedure TForm1.ModifyClick(Sender: TObject);
var
  I         : Integer;
  Path      : string;
  Found     : Integer;
  SearchRec : TSearchRec;
  FileList  : TStringList;
  Stopwatch : TStopwatch;
begin
  Path := 'c:\zzz\svg\'; // 默认路径，可以修改为 ExtractFilePath(Application.ExeName)
  
  // 增加目录选择对话框，以防固定路径不存在
  if not SelectDirectory('选择 SVG 文件所在目录', '', Path) then
    Exit;

  Path := IncludeTrailingPathDelimiter(Path);
  Memo1.Lines.Clear;
  Memo1.Lines.Add('开始扫描目录: ' + Path);
  Application.ProcessMessages;

  FileList := TStringList.Create;
  try
    Found := FindFirst(Path + '*.svg', faNormal, SearchRec);
    try
      while Found = 0 do
      begin
        FileList.Add(Path + SearchRec.Name);
        Found := FindNext(SearchRec);
      end;
    finally
      FindClose(SearchRec);
    end;

    if FileList.Count = 0 then
    begin
      Memo1.Lines.Add('该目录下未找到 SVG 文件。');
      Exit;
    end;

    FileList.Sort;
    Memo1.Lines.Add(Format('找到 %d 个文件，正在处理...', [FileList.Count]));
    Application.ProcessMessages;

    Stopwatch := TStopwatch.StartNew;

    for I := 0 to FileList.Count - 1 do
    begin
      try
        ProcessSVGFile(FileList[I]);
        Memo1.Lines.Add(Format('[%d/%d] %s', [I + 1, FileList.Count, ExtractFileName(FileList[I])]));
      except
        on E: Exception do
          Memo1.Lines.Add(Format('[%d/%d] 处理失败 %s: %s', [I + 1, FileList.Count, ExtractFileName(FileList[I]), E.Message]));
      end;
      
      // 保持界面响应
      if I mod 10 = 0 then
        Application.ProcessMessages;
    end;

    Stopwatch.Stop;
    Memo1.Lines.Add(Format('Complete! 共处理 %d 个文件，耗时 %.2f 秒。', 
      [FileList.Count, Stopwatch.Elapsed.TotalSeconds]));
  finally
    FileList.Free;
  end;
end;

end.
