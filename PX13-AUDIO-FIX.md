# ASUS ProArt PX13 HN7306 — CachyOS ses/stereo fix

## Amaç

Bu dosya ASUS ProArt PX13 HN7306 cihazında CachyOS/Linux altında dahili hoparlörlerin tek taraftan veya mono çalışması durumunda uygulanacak kalıcı çözümü açıklar.

Ana kurulum dosyası:

`px13-cachos-fix.sh`

Fresh CachyOS kurulumundan sonra bu dosyanın çalıştırılması, gerekli kernel build/header ortamını hazırlamayı, fix kaynaklarını almayı ve PX13 için gerekli kernel/UCM/PipeWire yapılandırmasını kurmayı hedefler.

## Bizim cihazda tespit edilen gerçek problem

Cihazın dahili hoparlörleri iki adet **TI TAS2783 SmartAmp** codec kullanıyor. Bunlar AMD SoundWire üzerinden sisteme bağlanıyor.

Bizim sistemde:

- ALSA kartı: `amd-soundwire`
- SoundWire hoparlör endpoint'i: `hw:1,2`
- Amp 1: `tas2783-1`
- Amp 2: `tas2783-2`
- Kernel: CachyOS `7.2.9-1-cachyos`

Sorunun donanım arızası olmadığı doğrudan ALSA testiyle doğrulandı.

Başlangıçta iki TAS2783 de aynı kanala atanmıştı:

```text
tas2783-1 Channel Playback = Left
tas2783-2 Channel Playback = Left
```

Bu nedenle iki fiziksel amplifikatör de sol kanal sesini alıyordu. Sağ kanal testi yapıldığında sağ hoparlörden ses gelmiyordu.

Çözüm:

```text
tas2783-1 = Left
tas2783-2 = Right
```

Bu değişiklikten sonra:

```text
speaker-test -D hw:1,2 -c 2 -t sine -l 1 -s 2
```

ile gerçek sağ hoparlörden ses geldi ve daha sonra:

```text
speaker-test -D pulse -c2 -l1 -t wav
```

çıktısı:

```text
Front Left
Front Right
```

oldu. Fiziksel sol/sağ stereo doğru çalıştı.

## Neden normal Linux kurulumu bunu kendiliğinden yapmıyor?

Linux 7.1 ile TAS2783 için yeni upstream sürücü geldi. PX13'te ise ASUS ACPI tabloları TAS2783'ün gerekli SDCA/DisCo fonksiyon bilgisini yeterince sağlamadığı için sürücü statik initialization yoluna düşüyor.

Bu initialization iki amplifikatöre de aynı DSP cluster/channel index'ini veriyor. Sonuç olarak iki amp aynı kanala bağlanabiliyor.

Upstream sürücüde `Channel Playback` isimli kullanıcı kontrolü bulunmadığı için userspace'in:

```text
tas2783-1 -> Left
tas2783-2 -> Right
```

şeklinde düzeltme yapabileceği bir kontrol de yok.

Fix bu nedenle upstream TAS2783 sürücüsünün küçük bir türetilmiş kernel modülünü kullanıyor ve `Channel Playback` kontrolünü ekliyor.

## Fix'in yaptığı işler

Kurulum, PX13 için mevcut `ftoleedo/px13-audio-fix` çözümünü kullanır.

### 1. Kernel modülü

Patched `snd-soc-tas2783-sdw` modülü oluşturulur.

Eklenen temel kontrol:

```text
Channel Playback
    Off
    Left
    Right
```

Kurulum mümkünse DKMS kullanır. Böylece yeni kernel kurulduğunda modül tekrar derlenebilir.

### 2. UCM yapılandırması

ALSA UCM'de TAS2783 için eksik yapılandırmalar eklenir.

Özellikle iki amp şu şekilde atanır:

```text
tas2783-1 Channel Playback = Left
tas2783-2 Channel Playback = Right
```

UCM ayrıca kart için gerçek `CardLongName` değerini kurulum sırasında tespit eder. Bu önemlidir; ASUS PX13'ün farklı SKU'larında bu değer değişebilir.

### 3. Speaker profili

UCM'nin `HiFi` profilinde gerçek `Speaker` cihazı oluşturduğu doğrulanır.

Kurulum `Speaker` bulunamazsa başarılı olmuş gibi devam etmez.

### 4. PipeWire

PipeWire/WirePlumber yeniden başlatılır ve SoundWire kartının `HiFi` profili seçilir.

Hoparlör sink'i varsayılan yapılır.

### 5. ALSA state

Çalışan ALSA durumu `alsactl store` ile kaydedilir.

### 6. RT721 jack codec

Bazı kernel sürümlerinde PX13'ün `rt721-sdca` jack codec'i runtime suspend sonrasında düzgün geri dönemeyebiliyor. Bu durumda tüm HiFi profili ve dolayısıyla dahili Speaker sink'i kaybolabiliyor.

Fix gerektiğinde:

```text
90-px13-rt721-no-autosuspend.rules
```

kuralını kurarak bu codec'in runtime suspend olmasını engeller.

## Suspend/resume konusu

Stereo fix ile suspend/resume fix aynı şey değildir.

PX13'te s2idle sonrasında SoundWire cihazlarının kaybolması veya TAS2783 DSP firmware'inin yeniden yüklenmemesi gibi ikinci bir problem oluşabilir.

Repo bunun için ayrıca `install-resume-recovery.sh` mekanizmasına sahiptir.

Bu mekanizma kurulursa resume sonrasında gerektiğinde SoundWire/ACP stack'i yeniden yükleyip TAS2783 firmware'ini tekrar yükler ve PipeWire'ı yeniden başlatır.

## Fresh CachyOS kurulumu sonrası kullanım

1. Bu `px13-cachos-fix.sh` dosyasını çalıştırılabilir yapın.
2. Normal kullanıcı olarak çalıştırın.
3. Script gerekli sudo işlemlerini kendisi yapar.
4. İnternet bağlantısı gerekir; script çözüm deposunu indirir.
5. Kurulum tamamlandığında stereo testinde hem `Front Left` hem `Front Right` görülmelidir.

Scripti `sudo` ile başlatmak yerine normal kullanıcı olarak çalıştırmak tercih edilir; çünkü PipeWire/WirePlumber kullanıcı oturumunda çalışır.

## Önemli: kernel güncellemeleri

Bu çözümün en önemli noktası kernel modülünün kernel sürümüyle uyumlu olmasıdır. Kernel API'leri 7.1, 7.2 ve 7.3 serileri arasında değişmiştir.

Bu nedenle modülün sabit bir `.ko` dosyasını yıllarca saklamak doğru değildir.

Kurulum scripti hedef kernel'in header'larını kullanarak modülü yeniden oluşturur. DKMS kullanılıyorsa sonraki kernel güncellemelerinde de yeniden build edilmesi amaçlanır.

Kernel güncellemesinden sonra ses tekrar tek kanala düşerse ilk kontrol:

```bash
bash /var/tmp/px13-audio-fix/check-audio.sh
```

## Şu anki doğrulanmış sonuç

Bu PX13 üzerinde çözüm uygulandıktan sonra:

```text
tas2783-1: values=1
tas2783-2: values=2
```

ve stereo testinde:

```text
Front Left
Front Right
```

elde edildi.

Bu, problemin fiziksel hoparlör arızası değil, TAS2783 kanal eşlemesi + Linux driver/UCM yapılandırması olduğunu doğruluyor.

## Kaynak

Çözüm deposu:

https://github.com/ftoleedo/px13-audio-fix

Bu repository'nin README'si problemin Linux 7.1+ TAS2783 driver davranışını, PX13 SoundWire yapısını, UCM eksiklerini, kanal eşleme problemini ve suspend/resume problemlerini ayrıntılı olarak açıklamaktadır.
