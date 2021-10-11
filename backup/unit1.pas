unit Unit1;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, Dialogs, StdCtrls, TAGraph,
  TASeries, TAIntervalSources, TATransformations;

type

  { TMainForm }

  TMainForm = class(TForm)
    ButtonColorChange: TButton;
    ButtonOpenFile: TButton;
    ButtonChooseThePath: TButton;
    ColorChange: TColorDialog;
    EditFrequency: TEdit;
    Label1: TLabel;
    LabelEditFrequency: TLabel;
    OpenDialog: TOpenDialog;
    SaveDialog: TSaveDialog;
    SaveToFile: TButton;
    ButtonSaveToFile: TButton;
    ButtonRun: TButton;
    Chart1: TChart;
    Chart1LineSeries1: TLineSeries;
    Memo: TMemo;
    procedure ButtonColorChangeClick(Sender: TObject);
    procedure ButtonOpenFileClick(Sender: TObject);
    procedure ButtonChooseThePathClick(Sender: TObject);
    procedure ButtonRunClick(Sender: TObject);
    procedure ButtonSaveToFileClick(Sender: TObject);
    procedure ChartAxisTransformations1UserDefinedAxisTransform1AxisToGraph(
      AX: Double; out AT: Double);
    procedure ChartAxisTransformations1UserDefinedAxisTransform1GraphToAxis(
      AX: Double; out AT: Double);
    procedure FormCreate(Sender: TObject);
  private

  public

  end;

var
  MainForm: TMainForm;
  SaveFilePath: string;
  OpenFilePath: string;

implementation

{$R *.lfm}

{ TMainForm }

procedure TMainForm.ButtonRunClick(Sender: TObject);

const
  Primary_Pit_size = 10; //Начальное значение размера участка ямы
  Primary_Impact_size = 0.3; //Начальное значение размера участка удара
  Primary_Noise_size = 40; //Начальное значение размера участка шума
  FreeFallSensitivityLimit = 0; // Граница чувствительности свободного падения
  Multiplier_Comparison_Max_Value_For_Short_fall = 0.6; // Коэф. чтобы понять, что попали в небольшую пропасть (обрыв)
  Multiplier_Comparison_Max_Value_For_Long_fall = 0.8; // Коэф. чтобы понять, что попали в большую пропасть (обрыв)
  Noise_min_value = -0.7; // Минимальное значение ускорения, чтобы определить шум
  Noise_max_value = 1.0;  // Максимальное значение ускорения, чтобы определить шум
  FuturePoint = 0.08;
var
    Pit_size:integer;//1000 было для 100кГц // Максимальное количество подряд идущих точек для определения участка как яма
    Impact_size:integer;//30 было для 100кГц // Максимальное количество подряд идущих точек для определения участка как удар
    Noise_size:integer;//4000 было для 100кГц // Максимальное количество подряд идущих точек для определения участка как шум.
    s:TlineSeries;
    f:textFile;
    CountPoint:integer; // количество точек
    MainPoint:array of double; // массив точек (ускорения)
    EditFrequencyValue:double; // введенная частота

    flag_negative_area:boolean;  // нахождение попадания в отрицательную область (но не означает, что мы нашли яму)
    FreeFallMoment:boolean; //наличие области свободного падения (далее "яма")

    flag_positive_area:boolean; // нахождение попадания в положительную область (но не означает, что мы нашли удар)
    Impact_In_Progress:boolean; // флаг на то, что удар находится в процессе (если так можно сказать)

    flag_area_Noise:boolean; // нахождение окончания колебаний (попадаем в шум)
    flag_Noise_moment:boolean; // нахождение попадания в область шума (но не означает, что мы нашли шум)

    j:integer; // счетчик
    StartFreeFall:integer; // точка начала свободного падения
    CountFreeFall:integer; // количество вхождений в отрицательную область
    StartNoise:integer; // точка начала шума
    CountNoise:integer; // количество вхождений в область шума

    Count_Moment_Of_Impact:integer; // количество точек после момента удара
    Starting_Point_Impact:integer; // точка удара
    Number_Output:integer; // номер вывода

    Max_Value:double; // Потенциальная ключевая точка
    Max_Value_coord:integer; // Индекс максимальной точки в массиве
    Max_Value_flag:boolean; // Флаг надобности поиска ключевой точки
    Max_Find_Complete:boolean; // Флаг, что найдена ключевая точка

    Max_Point:double;
    Min_Point:double;
begin
 Memo.Clear;
 AssignFile(f,OpenFilePath);
 reset(f);
 CountPoint:=0;
 Chart1LineSeries1.clear;
 Memo.Lines.Clear;
 while not eof(f) do begin
   inc(CountPoint);
   Setlength(MainPoint,CountPoint);
   try
     readln (f,MainPoint[CountPoint-1]);
     if (MainPoint[CountPoint-1] > Max_Point) then
       Max_Point:=MainPoint[CountPoint-1];
     if (MainPoint[CountPoint-1] < Min_Point) then
       Min_Point:=MainPoint[CountPoint-1];
   except
     showmessage('Возможно, был выбран неверный файл.');
     OpenFilePath:='main.txt';
     exit;
   end;
   //Memo.Lines.Add(FloatToStr(Point[CountPoint-1]));
  end;
  //Memo.Lines.Add('Done');
  closeFile (f);

  EditFrequencyValue:=StrToFloat(EditFrequency.Text);
  Memo.lines.add('Введенная частота = '+ FloatToStr(EditFrequencyValue) +'кГц');

  for j:=0 to CountPoint-1 do
    Chart1LineSeries1.AddXY(j/(EditFrequencyValue * 1000),MainPoint[j]);

  // Инициализация
  flag_positive_area:=false;
  Impact_In_Progress:=false;

  flag_negative_area:=false;
  FreeFallMoment:=false;
  flag_Noise_moment:=false;
  Max_Value_flag:=false;
  flag_area_Noise:=false;
  Max_Find_Complete:=false;

  CountFreeFall:=0;
  Count_Moment_Of_Impact:=0;

  Starting_Point_Impact:=0;
  Max_Value:=FreeFallSensitivityLimit;
  Max_Value_coord:=0;

  Number_Output:=0;
  StartNoise:=0;
  CountNoise:=0;
  Pit_size := trunc(Primary_Pit_size * EditFrequencyValue);
  Impact_size := trunc(Primary_Impact_size * EditFrequencyValue);
  Noise_size := trunc(Primary_Noise_size * EditFrequencyValue);


  // Пробегаемся по всем точкам
  for j:=0 to CountPoint-1 do begin

    // Если ускорение меньше границы чувствительности свободного падения
    if (MainPoint[j] < FreeFallSensitivityLimit) then begin
      // Мы нашли потенциальное свободное падение. (яму)
      // Нашли точку начала свободного падения и не нашли яму
      // ставим флаг, что нашли отрицательную область
      if (flag_negative_area = false) and (FreeFallMoment = false) then begin
       StartFreeFall:=j;
       flag_negative_area:=true;
      end;
    end
    // Если ускорение больше границы чувствительности свободного падения
    else
      // Если была яма и не было вхождения в положительную область
      if (FreeFallMoment = true) and (flag_positive_area = false) then
        // тогда мы нашли положительную область и записываем ВОЗМОЖНУЮ точку удара
        begin
          flag_positive_area := true;
          Starting_Point_Impact := j;
        end;

    // Если было вхождение в положительную область
    if (flag_positive_area = true) then
      // Если ускорение больше границы чувствительности
      if (MainPoint[j] > FreeFallSensitivityLimit) then
        // Считаем количество точек после момента удара
        inc(Count_Moment_Of_Impact)
      else
        // Если вышли из положительной области
        begin
          // Устанавливаем флаг на положительную область false
          flag_positive_area := false;
          // то момента удара не было
          Count_Moment_Of_Impact := 0;
        end;

    // Если количество точек после момента удара больше 30(либо еще какого-то значения)
    // и если до этого не было удара
    if (Count_Moment_Of_Impact > Impact_size) and (Impact_In_Progress = false) then begin
       // Происходит удар
       Impact_In_Progress:=true;

       // Момент свободного падения нам не нужен = false
       FreeFallMoment:=false;
       // Обнуляем точку свободного падания
       StartFreeFall:=0;
       // Обнуляем количество точек в свободном падении
       CountFreeFall:=0;
       // Флаг на поиск ключевой точки делаем активной (задачу на поиск)
       Max_Value_flag:=True;
       // Присваиваем потенциальной ключевой точке значение точки начала удара (y)
       Max_Value:=MainPoint[j-Impact_size];
       // Присваиваем потенциальной ключевой точке значение точки начала удара (x)
       Max_Value_coord:=j-Impact_size;
       // Вывод в memo
       Memo.Lines.Add('Точка удара = '+ IntToStr(Starting_Point_Impact));
       // Отрисовка точки (в данном случае черная линия) на графике
      // s:=TLineSeries.Create(MainForm.Chart1);
     //  s.SeriesColor:= clLime;
     //  s.AddXY(Starting_Point_Impact/(EditFrequencyValue * 1000), Max_Point, '', 1);
     //  s.AddXY(Starting_Point_Impact/(EditFrequencyValue * 1000), Min_Point, '', 1);
     //  MainForm.Chart1.AddSeries(s);
      end;

    // Если активна задача поиска ключевой точки
    If (Max_Value_flag = true) then begin
      // Если текущее значение ускорения выше ускорения потенциальной ключевой точки
      if (MainPoint[j] > Max_Value) then begin
        // Если дальше в точке будет обрыв
        if (Max_Value * Multiplier_Comparison_Max_Value_For_Long_fall > MainPoint[j+3]) then begin
          // Задача поиска ключевой точки становится неактивна
          Max_Value_flag:=False;
          Max_Find_Complete:=true;
          // Вывод
          Memo.Lines.Add('Максимум = ' + IntToStr(Max_Value_coord));
          Memo.Lines.Add('Значение максимума = ' + FloatToStr(MainPoint[Max_Value_coord]));
          // Отрисовка точки (в данном случае черная линия) на графике
       //   s:=TLineSeries.Create(MainForm.Chart1);
       //   s.SeriesColor:= clblue;
       //   s.AddXY(Max_Value_coord/(EditFrequencyValue * 1000), Max_Point, '', 1);
        //  s.AddXY(Max_Value_coord/(EditFrequencyValue * 1000), Min_Point, '', 1);
        //  MainForm.Chart1.AddSeries(s);
        end
        else begin
          // Если в точке не будет обрыва, тогда
          // присваиваем новые значения максимум в x и y
          Max_Value:=MainPoint[j];
          Max_Value_coord:=j;
        end;
      end
      // Если текущее значение ускорения меньше ускорения потенциальной ключевой точки
      else if (Max_Value * Multiplier_Comparison_Max_Value_For_Short_fall > MainPoint[j]) then begin
        // Задача поиска ключевой точки становится неактивна
        Max_Value_flag:=False;
        Max_Find_Complete:=true;
        // Вывод
        Memo.Lines.Add('Максимум = ' + IntToStr(Max_Value_coord));
        Memo.Lines.Add('Значение максимума = ' + FloatToStr(MainPoint[Max_Value_coord]));
        // Отрисовка точки (в данном случае черная линия) на графике
      //  s:=TLineSeries.Create(MainForm.Chart1);
     //  s.SeriesColor:= clblue;
       // s.AddXY(Max_Value_coord/(EditFrequencyValue * 1000), Max_Point, '', 1);
       // s.AddXY(Max_Value_coord/(EditFrequencyValue * 1000), Min_Point, '', 1);
      //  MainForm.Chart1.AddSeries(s);
      end;
    end;

    // Если была найдена отрицательная область, тогда
    if (flag_negative_area = true) then
       // Если ускорение меньше границы чувствительности
      if (MainPoint[j] < FreeFallSensitivityLimit) then
        // Увеличиваем количество точек, идущих подряд в отрицательной области
        inc(CountFreeFall)
      else begin
        // Иначе мы вышли из отрицательной области
        // Убираем флаг вхождения в отрицательную область
        flag_negative_area:=false;
        // Обнуляем количество идущих подряд точек в отрицательной области
        CountFreeFall:=0;
      end;

    // Если была найдена ключевая точка
    if (Max_Find_Complete = true) then
      begin
        // Если текущее ускорение не находится в промежутке определения шума
        if ((MainPoint[j] > Noise_min_value) and (MainPoint[j] < Noise_max_value)) then
          begin
            // Если шума еще не было и еще не заходили в область шума
            if (flag_Noise_moment = false) and (flag_area_Noise = false) then
            begin
              // В область шума зашли и запомнили координату начала шума
              flag_area_Noise := true;
              StartNoise:=j;
            end;
           // Считаем количество точек подряд в шуме
           inc(CountNoise);
          end
        // Если текущее ускорение находится вне промежутка
         else
         begin
           // Обнуляем количество подряд идущих точек и выходим из шума
           CountNoise:=0;
           flag_area_Noise:=false;
         end;
         // Если количество подряд идущих точек больше того, которое необходимо для определения шума
         // и шум закончился
         if (CountNoise > Noise_size) and (flag_Noise_moment = false) then
           begin
             // Ставим флаг на нахождение ключевой точки false
             Max_Find_Complete:=false;
             // Флаг на нахождение шума true
             flag_Noise_moment:=true;
             // Вышли из области шума
             flag_area_Noise:=false;
             // Отрисовываем
             Memo.Lines.Add( 'Окончание колебаний = ' +IntToStr(StartNoise));
           //  s:=TLineSeries.Create(MainForm.Chart1);
           //  s.SeriesColor:= clFuchsia;
           //  s.AddXY(StartNoise/(EditFrequencyValue * 1000), Max_Point, '', 1);
           //  s.AddXY(StartNoise/(EditFrequencyValue * 1000), Min_Point, '', 1);
           //  MainForm.Chart1.AddSeries(s);
           end;
      end;

    // Если количество подряд идущих точек в отрицательной области больше 1000 и
    // если мы еще не входили в яму
    if (CountFreeFall > Pit_size) and (FreeFallMoment = false) then begin
      // Если было вхождение в положительную область, тогда отменяем ее
      if (Impact_In_Progress = true) then
        Impact_In_Progress:=false;  //*позже убрать в другое место*

      if (flag_Noise_moment = true) then
        flag_Noise_moment:=false;

      flag_negative_area:=false;
      // Обнуляем точку начала удара
      // Обнуляем количество точек после удара
      // Ставим флаг на то, что нашли яму
      Starting_Point_Impact := 0;
      Count_Moment_Of_Impact := 0;
      FreeFallMoment:=true;
      inc(Number_Output);
      if (Number_Output > 1) then
        Memo.Lines.Add(' ');
      Memo.Lines.Add('[' + IntToStr(Number_Output)+ '] Точка начала свободного падения = ' +IntToStr(StartFreeFall));
      Memo.Lines.Add('[' + IntToStr(Number_Output)+ ']');
     // s:=TLineSeries.Create(MainForm.Chart1);
     // s.SeriesColor:= clpurple;
     // s.AddXY(StartFreeFall/(EditFrequencyValue * 1000), Max_Point, '', 1);
      //s.AddXY(StartFreeFall/(EditFrequencyValue * 1000), Min_Point, '', 1);
     // MainForm.Chart1.AddSeries(s)
    end;
  end;

end;

// Просто чтение файлов для удобства
procedure TMainForm.ButtonChooseThePathClick(Sender: TObject);
begin
  SaveDialog.DefaultExt:='txt';
  If (not (SaveDialog.Execute)) then
    exit
  else begin
    SaveFilePath:=SaveDialog.FileName;
    if (SaveFilePath = '') then
      Memo.Lines.SaveToFile(ExtractFilePath(Application.ExeName) + 'Text.txt')
    else begin
      if (pos('.txt',SaveFilePath) < 0) then
        SaveFilePath:=SaveFilePath+'.txt';
      Memo.Lines.SaveToFile(SaveFilePath);
    end;
  end;
end;

procedure TMainForm.ButtonOpenFileClick(Sender: TObject);
begin
  If (not (OpenDialog.Execute)) then
    exit
  else begin
    OpenFilePath:=OpenDialog.FileName;
     Chart1LineSeries1.clear;
     Memo.Lines.Clear;
    ButtonRunClick(Sender);
  end;
end;

procedure TMainForm.ButtonColorChangeClick(Sender: TObject);
var
    ChartColor:TColor;
begin
  If (ColorChange.Execute) then begin
    ChartColor:=ColorChange.Color;
    Chart1.BackColor:=ChartColor;
  end
  else exit;
end;

procedure TMainForm.ButtonSaveToFileClick(Sender: TObject);
begin
  if (SaveFilePath = '') then
    Memo.Lines.SaveToFile(ExtractFilePath(Application.ExeName) + 'ResultOfCalculation.txt');
end;

procedure TMainForm.ChartAxisTransformations1UserDefinedAxisTransform1AxisToGraph
  (AX: Double; out AT: Double);
begin

end;

procedure TMainForm.ChartAxisTransformations1UserDefinedAxisTransform1GraphToAxis
  (AX: Double; out AT: Double);
begin
  AX:=1000;
end;

procedure TMainForm.FormCreate(Sender: TObject);
begin
  Memo.Clear;
  SaveFilePath:='';
  OpenFilePath:='1.txt';
end;

end.

