<#
    Sprawdz-Srodowisko.ps1
    Kurs "Kryptografia w praktyce" - laboratorium L0.2 (lekcja 3).

    Do czego służy:
        sprawdza, czy na tej stacji Windows jest komplet narzędzi kursu.
        Każda pozycja kończy się jawnym "OK" albo "BRAK". Pozycja, której
        NIE DA SIĘ sprawdzić (typowo układ TPM bez uprawnień administratora),
        kończy się trzecim wynikiem: "[  ?  ]" - "nie mogę sprawdzić".
        To celowe: "nie mam uprawnień, żeby sprawdzić" to nie to samo, co "nie ma".

    Skąd wziąć ten plik (zwykłe okno PowerShella, w maszynie):
        curl.exe -fsSLO https://raw.githubusercontent.com/adminakademia/kryptografia/main/03_narzedzia_i_weryfikacja/SHA256SUMS
        curl.exe -fsSLO https://raw.githubusercontent.com/adminakademia/kryptografia/main/03_narzedzia_i_weryfikacja/Sprawdz-Srodowisko.ps1

    W PowerShellu "curl" bez rozszerzenia to alias na Invoke-WebRequest, który
    nie zna przełączników curla. W całym kursie na Windowsie piszemy "curl.exe".

    Weryfikacja sumy PRZED uruchomieniem (ta sama pętla, co w lekcji 2 przy
    plikach .ova; "Where-Object" pomija komentarze, "Test-Path" pomija pliki
    jeszcze niepobrane):
        Get-Content .\SHA256SUMS | Where-Object { $_ -notmatch '^\s*#' -and $_.Trim() } | ForEach-Object {
          $suma, $plik = $_ -split '\s+', 2
          $plik = $plik.Trim().TrimStart('*')
          if (Test-Path $plik) { '{0,-28} {1}' -f $plik, ((Get-FileHash $plik -Algorithm SHA256).Hash -eq $suma) }
        }

    Jak uruchomić (PowerShell URUCHOMIONY JAKO ADMINISTRATOR), ścieżką
    bezwzględną, BEZ zmiany katalogu:
        Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
        & "$env:USERPROFILE\Sprawdz-Srodowisko.ps1"

    Zapis wyniku do pliku (odpowiednik "tee" z Linuksa):
        & "$env:USERPROFILE\Sprawdz-Srodowisko.ps1" -Zapisz

    Raport zapisuje się LOKALNIE, do katalogu domowego. Do folderu wymiany
    przenosisz go osobnym poleceniem, Z OKNA ZWYKŁEGO - zasoby sieciowe bywają
    mapowane osobno dla sesji podniesionej i okno administratora może zasobu
    \\VBOXSVR w ogóle nie widzieć:
        Copy-Item .\narzedzia-win11-nowak.txt \\VBOXSVR\wymiana\

    Parametry:
        -Zapisz            dodatkowo zapisuje raport do pliku
        -SciezkaRaportu    gdzie zapisać raport; domyślnie
                           $env:USERPROFILE\narzedzia-<nazwa-maszyny>.txt

    Pozycja z układem TPM sprawdzana jest na OBU stacjach Windows, bezwarunkowo:
    vTPM jest w obrazie obu maszyn (decyzja autora, 2026-08-20) i nie ma czego
    dokładać. Dawny parametr -Tpm był potrzebny tylko wtedy, gdy skrypt zgadywał
    po nazwie maszyny, którą stację ma sprawdzać - został usunięty.

    Kody wyjścia:
        0 - komplet, ani jednej pozycji BRAK
        1 - co najmniej jedna pozycja BRAK
        2 - braków nie ma, ale co najmniej jednej pozycji nie dało się sprawdzić

    Kodowanie pliku: UTF-8 z BOM (Windows PowerShell 5.1 czyta plik bez BOM
    jako ANSI i polskie znaki zamieniają się w krzaki). Końce linii: CRLF.

    Dlaczego napisy WYPISYWANE NA EKRAN są bez polskich znaków:
        konsola Windows PowerShell 5.1 pracuje domyślnie ze stroną kodową
        systemu, a nie z UTF-8, i znaki spoza niej wychodzą jako znaki zapytania.
        Raport z tego skryptu kursant wkleja do pliku oddawanego, więc ma być
        czytelny wszędzie. Komentarze i dokumentacja - normalnie po polsku.
#>

[CmdletBinding()]
param(
    [switch] $Zapisz,
    [string] $SciezkaRaportu = "$env:USERPROFILE\narzedzia-$env:COMPUTERNAME.txt"
)

$ErrorActionPreference = 'Continue'

$script:LicznikOk    = 0
$script:LicznikBrak  = 0
$script:LicznikNiewi = 0
$script:Raport       = New-Object System.Collections.ArrayList

# ---------------------------------------------------------------------------
# Funkcje pomocnicze
# ---------------------------------------------------------------------------

function Write-Wiersz {
    param([string] $Tekst)
    Write-Host $Tekst
    [void] $script:Raport.Add($Tekst)
}

function Write-Ok {
    param([string] $Etykieta, [string] $Wartosc)
    Write-Wiersz ("[ OK  ]  {0,-16} {1}" -f $Etykieta, $Wartosc)
    $script:LicznikOk++
}

function Write-Brak {
    param([string] $Etykieta, [string] $Wartosc)
    Write-Wiersz ("[ BRAK]  {0,-16} {1}" -f $Etykieta, $Wartosc)
    $script:LicznikBrak++
}

function Write-NieWiem {
    param([string] $Etykieta, [string] $Wartosc)
    Write-Wiersz ("[  ?  ]  {0,-16} {1}" -f $Etykieta, $Wartosc)
    $script:LicznikNiewi++
}

function Write-Info {
    param([string] $Etykieta, [string] $Wartosc)
    Write-Wiersz ("[ INFO]  {0,-16} {1}" -f $Etykieta, $Wartosc)
}

# Jednorazowe wczytanie listy zainstalowanych programow z rejestru.
# Czytamy rejestr, a nie "winget list", bo rejestr odpowiada od razu
# i podaje numer wersji, ktory jest nam potrzebny do noty wersji.
function Get-ZainstalowaneProgramy {
    if ($null -ne $script:ProgramyCache) { return $script:ProgramyCache }

    $sciezki = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )

    $lista = @()
    foreach ($sciezka in $sciezki) {
        try {
            $wpisy = Get-ItemProperty -Path $sciezka -ErrorAction Stop |
                     Where-Object { $_.DisplayName } |
                     Select-Object DisplayName, DisplayVersion
            if ($wpisy) { $lista += $wpisy }
        } catch {
            # Brak galezi rejestru to normalna sytuacja - idziemy dalej.
        }
    }

    $script:ProgramyCache = $lista
    return $lista
}

# Sprawdza pozycje "program graficzny": najpierw rejestr, potem plik zapasowy.
function Test-Program {
    param(
        [string]   $Etykieta,
        [string[]] $Wzorce,
        [string[]] $PlikiZapasowe = @()
    )

    $programy = Get-ZainstalowaneProgramy
    foreach ($wzorzec in $Wzorce) {
        $trafienie = $programy | Where-Object { $_.DisplayName -like $wzorzec } | Select-Object -First 1
        if ($trafienie) {
            $wersja = $trafienie.DisplayVersion
            if ([string]::IsNullOrWhiteSpace($wersja)) { $wersja = 'obecny' }
            Write-Ok $Etykieta ("{0}  ({1})" -f $wersja, $trafienie.DisplayName)
            return
        }
    }

    foreach ($plik in $PlikiZapasowe) {
        if (Test-Path -LiteralPath $plik) {
            Write-Ok $Etykieta ("obecny  ({0})" -f $plik)
            return
        }
    }

    Write-Brak $Etykieta 'nie znaleziono programu'
}

# Sprawdza pozycje "polecenie": czy powloka umie je uruchomic.
function Test-Polecenie {
    param(
        [string] $Etykieta,
        [string] $Polecenie,
        [string] $Opis = 'polecenie dostepne'
    )

    $znalezione = Get-Command -Name $Polecenie -ErrorAction SilentlyContinue
    if ($znalezione) {
        Write-Ok $Etykieta $Opis
    } else {
        Write-Brak $Etykieta 'nie znaleziono polecenia'
    }
}

# ---------------------------------------------------------------------------
# Naglowek
# ---------------------------------------------------------------------------

$czyAdmin = $false
try {
    $tozsamosc = [Security.Principal.WindowsIdentity]::GetCurrent()
    $rola      = New-Object Security.Principal.WindowsPrincipal($tozsamosc)
    $czyAdmin  = $rola.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
} catch {
    $czyAdmin = $false
}

if ($czyAdmin) { $opisUprawnien = 'administrator' } else { $opisUprawnien = 'zwykle (bez podniesienia)' }

$system = (Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue).Caption
if ([string]::IsNullOrWhiteSpace($system)) { $system = 'Windows' }

Write-Wiersz '==========================================================================='
Write-Wiersz ' Sprawdz-Srodowisko.ps1 - kontrola warsztatu kursu (laboratorium L0.2)'
Write-Wiersz '==========================================================================='
Write-Wiersz (' Maszyna     : {0}' -f $env:COMPUTERNAME)
Write-Wiersz (' Uzytkownik  : {0}' -f $env:USERNAME)
Write-Wiersz (' System      : {0}' -f $system)
Write-Wiersz (' PowerShell  : {0}' -f $PSVersionTable.PSVersion.ToString())
Write-Wiersz (' Uprawnienia : {0}' -f $opisUprawnien)
Write-Wiersz (' Data        : {0}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))
Write-Wiersz '---------------------------------------------------------------------------'
Write-Wiersz ' Legenda:  [ OK  ] jest    [ BRAK] nie ma    [  ?  ] nie moge sprawdzic'
Write-Wiersz '           [ INFO] pozycja nieobowiazkowa - nie liczy sie jako BRAK'
Write-Wiersz ' Numery wersji przepisz do swojej noty wersji (zadanie 2 z lekcji 3).'
Write-Wiersz '---------------------------------------------------------------------------'

# ---------------------------------------------------------------------------
# Pozycje - narzedzia systemowe
# ---------------------------------------------------------------------------

Test-Polecenie 'Get-FileHash' 'Get-FileHash' 'polecenie dostepne (liczenie sum kontrolnych)'
Test-Polecenie 'certutil'     'certutil'     'polecenie dostepne (skroty i magazyn certyfikatow)'

# Dwie pozycje, na ktorych stoi caly kanal plikow kursu: "curl.exe" przywozi
# pliki lekcji do maszyny, "ssh" (a z nim "scp") przenosi pliki miedzy stacja
# a serwerami w lekcjach 6 i 9. Skrypt kontrolny, ktory ich nie sprawdza,
# powiedzialby "komplet" maszynie, na ktorej lekcja 6 sie wysypie.
Test-Polecenie 'curl.exe'     'curl.exe'     'polecenie dostepne (pobieranie plikow lekcji)'
Test-Polecenie 'ssh'          'ssh'          'polecenie dostepne (klient OpenSSH, razem z nim scp)'

# ---------------------------------------------------------------------------
# Pozycje - osiem NARZEDZI z listy winget.
# Lista instalacyjna ma dziewiata pozycje, Google Chrome, ale swiadomie
# jej tu NIE sprawdzamy: to nie narzedzie kursu, tylko wyrownanie startu
# dla osob z wlasna instalacja Windows. Jego brak niczego nie psuje,
# a raport tej lekcji ma byc wolny od pozycji "BRAK".
# ---------------------------------------------------------------------------

Test-Program -Etykieta 'Gpg4win/Kleop.' -Wzorce @('Gpg4win*', 'GNU Privacy Guard*') -PlikiZapasowe @(
    "$env:ProgramFiles (x86)\Gpg4win\bin\kleopatra.exe",
    "$env:ProgramFiles\Gpg4win\bin\kleopatra.exe"
)

Test-Program -Etykieta 'XCA' -Wzorce @('XCA*') -PlikiZapasowe @(
    "$env:ProgramFiles\xca\xca.exe",
    "$env:ProgramFiles (x86)\xca\xca.exe"
)

Test-Program -Etykieta 'VeraCrypt'   -Wzorce @('VeraCrypt*')
Test-Program -Etykieta 'KeePassXC'   -Wzorce @('KeePassXC*')
Test-Program -Etykieta 'PuTTY'       -Wzorce @('PuTTY*')
Test-Program -Etykieta 'Thunderbird' -Wzorce @('Mozilla Thunderbird*', 'Thunderbird*')
Test-Program -Etykieta 'Wireshark'   -Wzorce @('Wireshark*')
Test-Program -Etykieta '7-Zip'       -Wzorce @('7-Zip*')

# Npcap - osobna pozycja, bo to ON decyduje, czy Wireshark cokolwiek zobaczy.
# Wireshark bez Npcapa instaluje sie poprawnie i nie zglasza zadnego bledu.
$npcapZnaleziony = $false
$programy = Get-ZainstalowaneProgramy
$wpisNpcap = $programy | Where-Object { $_.DisplayName -like 'Npcap*' } | Select-Object -First 1
if ($wpisNpcap) {
    $wersjaNpcap = $wpisNpcap.DisplayVersion
    if ([string]::IsNullOrWhiteSpace($wersjaNpcap)) { $wersjaNpcap = 'obecny' }
    Write-Ok 'Npcap' $wersjaNpcap
    $npcapZnaleziony = $true
} else {
    $usluga = Get-Service -Name 'npcap' -ErrorAction SilentlyContinue
    if ($usluga) {
        Write-Ok 'Npcap' ('usluga npcap: {0}' -f $usluga.Status)
        $npcapZnaleziony = $true
    } elseif (Test-Path -LiteralPath "$env:SystemRoot\System32\Npcap") {
        Write-Ok 'Npcap' 'obecny (katalog System32\Npcap)'
        $npcapZnaleziony = $true
    }
}
if (-not $npcapZnaleziony) {
    Write-Brak 'Npcap' 'nie znaleziono - Wireshark nie przechwyci ruchu'
}

# ---------------------------------------------------------------------------
# Pozycja nieobowiazkowa: openssl w sciezce
# ---------------------------------------------------------------------------

$opensslWin = Get-Command -Name 'openssl' -ErrorAction SilentlyContinue
if ($opensslWin) {
    $wersjaOpenssl = 'obecny'
    try {
        $wynik = & openssl version
        if ($wynik) { $wersjaOpenssl = ($wynik | Select-Object -First 1).ToString().Trim() }
    } catch {
        $wersjaOpenssl = 'obecny (nie udalo sie odczytac wersji)'
    }
    Write-Ok 'openssl' $wersjaOpenssl
} else {
    Write-Info 'openssl' 'brak w sciezce - na Windowsie pozycja nieobowiazkowa'
}

# ---------------------------------------------------------------------------
# Uklad TPM - sprawdzany na OBU stacjach Windows, bezwarunkowo.
# vTPM jest w obrazie obu stacji (decyzja autora, 2026-08-20) - niczego sie
# nie doklada, wiec nie ma powodu rozgalezniac tej pozycji po nazwie maszyny.
# ---------------------------------------------------------------------------

Write-Wiersz '---------------------------------------------------------------------------'

try {
    $stanTpm = Get-Tpm -ErrorAction Stop

    # UWAGA, to jest sedno tej pozycji. Get-Tpm uruchomiony BEZ podniesionych
    # uprawnień nie zgłasza wyjątku - zwraca zwykły napis
    # "Administrator privilege is required to execute this command.".
    # Gdybyśmy sprawdzali tylko właściwość TpmPresent, dostalibyśmy $null,
    # czyli wartość fałszywą, i skrypt wypisałby "BRAK" - czyli zamieniłby
    # "nie mogę sprawdzić" na "nie ma". Dokładnie to, przed czym ostrzega lekcja.
    $stanNieczytelny = ($null -eq $stanTpm) -or
                       ($stanTpm -is [string]) -or
                       ($null -eq $stanTpm.TpmPresent)

    if ($stanNieczytelny) {
        $powod = 'polecenie Get-Tpm nie zwrocilo stanu ukladu'
        if ($stanTpm -is [string]) { $powod = ([string]$stanTpm).Trim() }
        Write-NieWiem 'TPM' $powod
        Write-Wiersz '         To NIE znaczy "nie ma TPM". To znaczy "nie moge sprawdzic".'
        Write-Wiersz '         Uruchom PowerShell jako administrator i sprobuj ponownie.'
    } elseif ($stanTpm.TpmPresent -and $stanTpm.TpmReady) {
        Write-Ok 'TPM' 'TpmPresent: True, TpmReady: True'
    } elseif ($stanTpm.TpmPresent) {
        Write-Brak 'TPM' ('TpmPresent: True, ale TpmReady: {0}' -f $stanTpm.TpmReady)
    } else {
        Write-Brak 'TPM' 'TpmPresent: False - modul powinien byc w obrazie; sprawdz w ustawieniach maszyny, czy nie zostal wylaczony'
    }
} catch {
    Write-NieWiem 'TPM' ('{0}' -f $_.Exception.Message)
    Write-Wiersz '         To NIE znaczy "nie ma TPM". To znaczy "nie moge sprawdzic".'
    Write-Wiersz '         Uruchom PowerShell jako administrator i sprobuj ponownie.'
}

# ---------------------------------------------------------------------------
# Podsumowanie
# ---------------------------------------------------------------------------

$razem = $script:LicznikOk + $script:LicznikBrak + $script:LicznikNiewi

Write-Wiersz '---------------------------------------------------------------------------'
Write-Wiersz (' PODSUMOWANIE: {0} pozycji  ->  {1} OK, {2} BRAK, {3} nie moge sprawdzic' -f `
    $razem, $script:LicznikOk, $script:LicznikBrak, $script:LicznikNiewi)

$kodWyjscia = 0
if ($script:LicznikBrak -gt 0) {
    Write-Wiersz ' Wynik: NIEKOMPLETNE.'
    Write-Wiersz ' Co teraz: polecenie instalacyjne dla kazdej pozycji BRAK stoi'
    Write-Wiersz '           w INSTRUKCJI LABORATORYJNEJ do tej lekcji, w zasobach'
    Write-Wiersz '           lekcji na platformie AdminAkademia.'
    $kodWyjscia = 1
} elseif ($script:LicznikNiewi -gt 0) {
    Write-Wiersz ' Wynik: bez brakow, ale co najmniej jednej pozycji nie dalo sie sprawdzic.'
    Write-Wiersz '        Powtorz w oknie uruchomionym jako administrator.'
    $kodWyjscia = 2
} else {
    Write-Wiersz ' Wynik: KOMPLET. Warsztat kursu jest na tej stacji kompletny.'
}
Write-Wiersz '==========================================================================='

if ($Zapisz) {
    # Domyslnie zapisujemy LOKALNIE, do katalogu domowego. Powod jest praktyczny:
    # skrypt uruchamiamy w oknie administratora, a ono nie zawsze widzi zasob
    # sieciowy \\VBOXSVR. Przeniesienie raportu do folderu wymiany robi sie
    # osobnym poleceniem Copy-Item, z okna zwyklego.
    $plikRaportu = $SciezkaRaportu
    try {
        $script:Raport | Out-File -FilePath $plikRaportu -Encoding utf8 -ErrorAction Stop
        Write-Host ("Raport zapisany: {0}" -f $plikRaportu)
        Write-Host 'Do folderu wymiany przenies go z okna ZWYKLEGO:'
        Write-Host ("  Copy-Item '{0}' \\VBOXSVR\wymiana\" -f $plikRaportu)
    } catch {
        Write-Host ("Nie udalo sie zapisac raportu do {0}" -f $plikRaportu)
        Write-Host ("Powod: {0}" -f $_.Exception.Message)
        Write-Host 'Skopiuj wynik z ekranu recznie albo wskaz inne miejsce zapisu:'
        Write-Host '  -SciezkaRaportu "C:\Users\<konto>\narzedzia-<nazwa-maszyny>.txt"'
    }
}

exit $kodWyjscia
