using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Threading;
namespace FVR.Monitoring.Client;
public partial class MainWindow : Window
{
    readonly DispatcherTimer _clock = new() { Interval = TimeSpan.FromSeconds(1) };
    int _zoomIndex;
    readonly string[] _zooms = ["1x","1.25x","1.5x","2x"];
    bool _audio;
    public MainWindow(){InitializeComponent();_clock.Tick+=(_,_)=>ClockText.Text=DateTime.Now.ToString("dd/MM/yyyy HH:mm:ss");_clock.Start();BuildGrid(2);}
    void BuildGrid(int side){VideoGrid.Children.Clear();VideoGrid.Rows=side;VideoGrid.Columns=side;int count=side*side;for(int i=0;i<count;i++){var border=new Border{Margin=new Thickness(2),Background=new SolidColorBrush(Color.FromRgb(5,7,10)),BorderBrush=new SolidColorBrush(Color.FromRgb(52,60,73)),BorderThickness=new Thickness(1)};var g=new Grid();g.Children.Add(new TextBlock{Text=$"TELA {i+1}\n\nAGUARDANDO CÂMERA",Foreground=new SolidColorBrush(Color.FromRgb(110,120,135)),HorizontalAlignment=HorizontalAlignment.Center,VerticalAlignment=VerticalAlignment.Center,TextAlignment=TextAlignment.Center});border.Child=g;VideoGrid.Children.Add(border);}StatusText.Text=$"Mosaico {side}x{side} • {count} posições";}
    void OpenSelected_Click(object s,RoutedEventArgs e){var name=(CameraList.SelectedItem as ListBoxItem)?.Content?.ToString()??"Câmera";StatusText.Text=$"{name} selecionada • RTSP/ONVIF será conectado ao Management Server";}
    void Grid1_Click(object s,RoutedEventArgs e)=>BuildGrid(1); void Grid2_Click(object s,RoutedEventArgs e)=>BuildGrid(2); void Grid3_Click(object s,RoutedEventArgs e)=>BuildGrid(3); void Grid4_Click(object s,RoutedEventArgs e)=>BuildGrid(4); void Grid8_Click(object s,RoutedEventArgs e)=>BuildGrid(8);
    void Audio_Click(object s,RoutedEventArgs e){_audio=!_audio;AudioButton.Content=_audio?"ÁUDIO ON":"ÁUDIO OFF";StatusText.Text=_audio?"Áudio seletivo ativado":"Áudio desligado";}
    void Zoom_Click(object s,RoutedEventArgs e){_zoomIndex=(_zoomIndex+1)%_zooms.Length;ZoomButton.Content=$"ZOOM {_zooms[_zoomIndex]}";StatusText.Text=$"Zoom digital {_zooms[_zoomIndex]}";}
    void VideoWall_Click(object s,RoutedEventArgs e)=>MessageBox.Show("Video Wall Controller - Etapa 10\nSelecione monitor, layout e câmeras no build completo.","FVR VMS",MessageBoxButton.OK,MessageBoxImage.Information);
    void EMap_Click(object s,RoutedEventArgs e)=>MessageBox.Show("E-Map / Layouts persistentes - Etapa 10\nA integração com PostgreSQL faz parte da solution completa.","FVR VMS",MessageBoxButton.OK,MessageBoxImage.Information);
    void Exit_Click(object s,RoutedEventArgs e)=>Close();
}
