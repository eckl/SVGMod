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
  Vcl.Graphics,
  Vcl.Controls,
  Vcl.Forms,
  Vcl.Dialogs,
  Vcl.StdCtrls,
  Vcl.Menus,
  Vcl.ComCtrls;

type
  TForm1 = class( TForm )
    Memo1: TMemo;
    MainMenu1: TMainMenu;
    Modify: TMenuItem;
    procedure ModifyClick( Sender: TObject );
  private
    { Private declarations }
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

type
  TStringListHelper = class helper for TStrings
  public
    // CaseSensitive: 是否区分大小写（默认 False，忽略大小写）
    function IndexOfPrefix( const APrefix: string; CaseSensitive: Boolean = False ): Integer;
  end;

function TStringListHelper.IndexOfPrefix( const APrefix: string; CaseSensitive: Boolean ): Integer;
var
  I: Integer;
begin
  Result := -1;
  for I  := 0 to Count - 1 do
  begin
    if CaseSensitive then
    begin
      // 区分大小写
      if StartsStr( APrefix, Strings[ I ] ) then
        Exit( I );
    end
    else
    begin
      // 忽略大小写
      if StartsText( APrefix, Strings[ I ] ) then
        Exit( I );
    end;
  end;
end;

procedure SVGRead( index: Integer ); forward;

function AddTxt( x, y: string; di: string; txt: string ): string; forward;

var
  T       : Cardinal;
  FileList: TStringList;

procedure SVGRead( index: Integer );
var
  I, j, idx, iend   : Integer;
  svg, anode        : TQXMLNode;
  LL, Ltxt          : TQXMLNode;
  Attrs             : TQXMLAttrs;
  No, Name          : string;
  rec               : TArray<string>;
  x, y              : string;
  height, width     : string;
  svgFile           : TStringList;
  Pattern1, Pattern2: string;
begin
  svg      := TQXMLNode.Create;
  anode    := TQXMLNode.Create;
  LL       := TQXMLNode.Create;
  Ltxt     := TQXMLNode.Create;
  svgFile  := TStringList.Create;
  Pattern1 := '手车|刀闸|地刀|开关';
  Pattern2 := '变|运维|';

  try
    svg.LoadFromFile( FileList[ index ] );
    svgFile.LoadFromFile( FileList[ index ], TEncoding.UTF8 );

    idx            := svgFile.IndexOfPrefix( '<symbol id="terminal"' );
    svgFile[ idx ] := ReplaceText( svgFile[ idx ], 'xMidYMid', 'xMinYMin' );

    Attrs  := svg[ 0 ].ItemWithAttrValue( 'g', 'id', 'Head_Layer' ).ItemByName( 'rect' ).Attrs;
    height := Attrs.ValueByName( 'height' );
    width  := Attrs.ValueByName( 'width' );

    idx            := svgFile.IndexOfPrefix( '<svg' );
    svgFile[ idx ] := TRegEx.Replace( svgFile[ idx ], 'viewBox="[^"]*"', Format( 'viewBox="%s"', [ '0,0,' + width + ',' + height ] ), [ roIgnoreCase ] );

    idx  := svgFile.IndexOf( '<g id="Text_Layer">' ) + 1;
    iend := svgFile.Count;
    while idx <= iend - 2 do
    begin
      if svgFile[ idx ] = '</g>' then
        Break;
      if not TRegEx.IsMatch( svgFile[ idx ], Pattern2 ) then
        svgFile.Delete( idx )
      else
        Inc( idx );
    end;
    for I := svgFile.IndexOf( '<g id="MeasurementValue_Layer">' ) to svgFile.Count - 1 do
    begin
      svgFile[ I ] := ReplaceText( svgFile[ I ], 'ssss', '' );
      svgFile[ I ] := ReplaceText( svgFile[ I ], '-00.00', '' );
      svgFile[ I ] := ReplaceText( svgFile[ I ], '-000', '' );
    end;
    LL    := svg[ 0 ].ItemWithAttrValue( 'g', 'id', 'MeasurementValue_Layer' );
    for I := 0 to LL.Count - 1 do
    begin
      Ltxt := LL.Items[ I ].ItemByName( 'text' );
      if Ltxt.Text = 'ssss' then
      begin
        x    := Ltxt.Attrs.ValueByName( 'x' );
        y    := Ltxt.Attrs.ValueByName( 'y' );
        name := LL.Items[ I ].ItemByName( 'metadata' ).ItemByName( 'cge:Meas_Ref' ).Attrs.ValueByName( 'ObjectName' );
        if name = '' then
          Continue;
        rec  := name.Split( [ '.' ] );
        name := ReplaceText( rec[ high( rec ) ], ':other', '' );
        if not TRegEx.IsMatch( name, Pattern1 ) then
          if not TRegEx.IsMatch( name, 'kV' ) then
          begin
            No := TRegEx.Match( name, '[0-9]{3,5}' ).Value;
            svgFile.Insert( svgFile.Count - 3, AddTxt( x, y, 'lr', No ) );
            name := ReplaceText( name, '_', '' );
            name := ReplaceText( name, No, '' );
            svgFile.Insert( svgFile.Count - 3, AddTxt( IntToStr( StrToInt( x ) + 15 ), IntToStr( StrToInt( y ) + 10 ), 'tb', name ) );
          end
          else
            svgFile.Insert( svgFile.Count - 3, AddTxt( x, IntToStr( StrToInt( y ) - 3 ), 'lr', name ) );
      end;
    end;
    svgFile.SaveToFile( FileList[ index ], TEncoding.UTF8 );
  finally
    svgFile.Free;
    svg.Free;
  end;
  Form1.Memo1.Lines.Add( IntToStr( index + 1 ) );
end;

procedure TForm1.ModifyClick( Sender: TObject );
var
  I        : Integer;
  path     : string;
  Found    : Integer;
  SearchRec: TSearchRec;
begin
  T        := GetTickCount;
  FileList := TStringList.Create;

  path := 'c:\zzz\svg\';

  Found := FindFirst( path + '*.svg', faNormal, SearchRec );
  while Found = 0 do
  begin
    FileList.Add( path + SearchRec.Name );
    Found := FindNext( SearchRec );
  end;
  FindClose( SearchRec );
  FileList.Sort;

  for I := 0 to FileList.Count - 1 do
  begin
    SVGRead( I );
  end;
  Memo1.Lines.Add( 'Complete!' );
end;

function AddTxt( x, y: string; di: string; txt: string ): string;
begin
  Result := '<text x="' + x + '" y="' + y + '" font-size="20" font-width="20" font-height="20" font-family="SimSun" ' + 'fill="rgb(0,255,0)" stroke="rgb(255,255,254)" writing-mode="' + di +
    '" Plane="0" AFMask="39039" xml:space="preserve">' + txt + '</text>';
end;

end.
