#!/usr/bin/env bash
#
# sprawdz-srodowisko.sh
# Kurs "Kryptografia w praktyce" - laboratorium L0.2 (lekcja 3).
#
# Do czego sluzy:
#   sprawdza, czy na tej maszynie sa DOSTEPNE POLECENIA calego warsztatu kursu.
#   Kazda pozycja konczy sie jawnym "OK" albo "BRAK". Na koncu jest podsumowanie
#   i kod wyjscia: 0 gdy komplet, 1 gdy czegokolwiek brakuje.
#
# Jak uruchomic (nie wymaga uprawnien administratora).
# Krok po kroku, w tej kolejnosci - najpierw lista sum, potem plik, potem
# weryfikacja, dopiero na koncu uruchomienie:
#   cd ~
#   curl -fsSLO https://raw.githubusercontent.com/adminakademia/kryptografia/main/03_narzedzia_i_weryfikacja/SHA256SUMS
#   curl -fsSLO https://raw.githubusercontent.com/adminakademia/kryptografia/main/03_narzedzia_i_weryfikacja/sprawdz-srodowisko.sh
#   ls -l sprawdz-srodowisko.sh
#   sha256sum --ignore-missing -c SHA256SUMS
#   bash sprawdz-srodowisko.sh
#   bash sprawdz-srodowisko.sh | tee ~/narzedzia-$(hostname).txt
#
# Wynik zabierasz z maszyny na swoj komputer poleceniem "scp" po sieci
# LAB-KRYPTO - z komputera, a nie z maszyny:
#   scp "kursant@172.16.0.10:~/narzedzia-*.txt" D:\lab-krypto\wymiana\
#
# Dlaczego "bash <plik>", a nie "./sprawdz-srodowisko.sh":
#   plik pobrany z sieci nie ma bitu wykonywalnosci ("ls -l" pokaze
#   "-rw-r--r--") i swiadomie mu go NIE NADAJEMY przed sprawdzeniem sumy.
#   Wywolanie przez "bash" pozwala uruchomic skrypt bez nadawania uprawnienia,
#   ktorego i tak nie potrzebujemy.
#
# Wazna zasada konstrukcyjna:
#   sprawdzamy obecnosc POLECEN (command -v), a nie obecnosc plikow pakietow.
#   Dzieki temu dziala test negatywny z punktu 7 lekcji: po przeniesieniu
#   dowiazania /usr/local/bin/testssl.sh skrypt MA pokazac "BRAK".
#
# Dziala na: Debian 13, Rocky Linux 10, Ubuntu Server 26.04 LTS.
# Konce linii: LF. Kodowanie: UTF-8.

set -u

# Sciezki systemowe. Czesc narzedzi tego kursu to programy administracyjne i lezy
# w /usr/sbin: na Rocky i Ubuntu katalog ten jest w PATH zwyklego uzytkownika,
# na Debianie NIE JEST. Bez tej linijki skrypt zglaszalby BRAK przy poprawnie
# zainstalowanych "john" i "cryptsetup" - czyli falszywy alarm, a fałszywy alarm
# uczy ignorowania alarmow. Sprawdzamy nadal POLECENIA, a nie pliki: test negatywny
# z punktu 7 lekcji dziala bez zmian, bo /usr/local/bin bylo w PATH od poczatku.
PATH="$PATH:/usr/sbin:/sbin"
export PATH

LICZNIK_OK=0
LICZNIK_BRAK=0
LICZNIK_INFO=0

# Rodzina systemu. Potrzebna przy dwoch pozycjach, ktorych RHEL 10 nie pakietuje.
RODZINA=$(. /etc/os-release 2>/dev/null; printf '%s %s' "${ID:-}" "${ID_LIKE:-}")
case "$RODZINA" in
    *rhel*|*fedora*|*centos*) RODZINA_RHEL=tak ;;
    *)                        RODZINA_RHEL=nie ;;
esac

# ---------------------------------------------------------------------------
# Funkcje pomocnicze
# ---------------------------------------------------------------------------

wypisz_ok() {
    printf '[ OK  ]  %-13s %s\n' "$1" "$2"
    LICZNIK_OK=$((LICZNIK_OK + 1))
}

wypisz_brak() {
    printf '[ BRAK]  %-13s %s\n' "$1" "$2"
    LICZNIK_BRAK=$((LICZNIK_BRAK + 1))
}

# Pozycja nieobowiazkowa na TEJ rodzinie systemow: jej brak nie jest bledem
# i nie psuje wyniku laboratorium.
wypisz_info() {
    printf '[ INFO]  %-13s %s\n' "$1" "$2"
    LICZNIK_INFO=$((LICZNIK_INFO + 1))
}

# Czy powloka umie uruchomic to polecenie?
mam_polecenie() {
    command -v "$1" >/dev/null 2>&1
}

# Wyciaga pierwszy ciag wygladajacy na numer wersji z pierwszych linii wyniku.
# Bierzemy tez stderr, bo czesc narzedzi wypisuje wersje wlasnie tam.
pierwsza_wersja() {
    "$@" 2>&1 | head -n 5 | grep -oE '[0-9]+\.[0-9]+([.a-zA-Z0-9_-]*)?' | head -n 1 |
        sed 's/[.,;:-]*$//'
}

# Pozycja nieobowiazkowa: jak wyzej, ale brak konczy sie statusem [ INFO],
# a nie [ BRAK]. Trzeci argument to powod, wypisywany kursantowi.
sprawdz_narzedzie_opcjonalne() {
    polecenie="$1"
    etykieta="$2"
    powod="$3"
    shift 3
    if ! mam_polecenie "$polecenie"; then
        wypisz_info "$etykieta" "$powod"
        return
    fi
    wersja=$(pierwsza_wersja "$@")
    if [ -z "$wersja" ]; then
        wersja="obecny"
    fi
    wypisz_ok "$etykieta" "$wersja"
}

# Standardowa pozycja: nazwa polecenia, etykieta w raporcie, polecenie wersji.
sprawdz_narzedzie() {
    polecenie="$1"
    etykieta="$2"
    shift 2
    if ! mam_polecenie "$polecenie"; then
        wypisz_brak "$etykieta" "nie znaleziono polecenia"
        return
    fi
    wersja=$(pierwsza_wersja "$@")
    if [ -z "$wersja" ]; then
        wersja="obecny"
    fi
    wypisz_ok "$etykieta" "$wersja"
}

# ---------------------------------------------------------------------------
# Naglowek
# ---------------------------------------------------------------------------

SYSTEM="nieznany"
if [ -r /etc/os-release ]; then
    SYSTEM=$(. /etc/os-release 2>/dev/null; printf '%s' "${PRETTY_NAME:-$NAME}")
fi

echo "==========================================================================="
echo " sprawdz-srodowisko.sh - kontrola warsztatu kursu (laboratorium L0.2)"
echo "==========================================================================="
printf ' Maszyna : %s\n' "$(hostname)"
printf ' System  : %s\n' "$SYSTEM"
printf ' Jadro   : %s\n' "$(uname -r)"
printf ' Data    : %s\n' "$(date '+%Y-%m-%d %H:%M:%S')"
echo "---------------------------------------------------------------------------"
echo " Legenda:  [ OK  ] polecenie dostepne     [ BRAK] polecenia nie ma"
echo "           [ INFO] pozycja nieobowiazkowa na tym systemie - nie liczy sie jako BRAK"
echo " Numery wersji przepisz do swojej noty wersji (zadanie 2 z lekcji 3)."
echo "---------------------------------------------------------------------------"

if [ "$(id -u)" -eq 0 ]; then
    echo " Uwaga: skrypt zostal uruchomiony jako root. To NIE jest potrzebne -"
    echo "        wszystkie sprawdzenia dzialaja na zwyklym koncie kursanta."
    echo "---------------------------------------------------------------------------"
fi

# ---------------------------------------------------------------------------
# Pozycje inwentarza - dokladnie ta sama lista, ktora instalowalismy
# w punktach 3, 4, 5 i 6 lekcji. Trzynascie narzedzi, czternascie sprawdzen.
# ---------------------------------------------------------------------------

# 1. openssl - wersja biblioteki i binarki
sprawdz_narzedzie openssl "openssl" openssl version -a

# 2. openssl - lista aktywnych dostawcow algorytmow.
#    To INNE pytanie niz "ktora to wersja": tu pytamy, jakie algorytmy
#    ta biblioteka faktycznie udostepnia. Wracamy do tego w rozdziale 15.
if mam_polecenie openssl; then
    DOSTAWCY=$(openssl list -providers 2>/dev/null \
        | awk '/^  [^ ]/ { gsub(/^[ \t]+|[ \t]+$/, "", $0); print }' \
        | paste -sd, - )
    if [ -n "$DOSTAWCY" ]; then
        wypisz_ok "providers" "$DOSTAWCY"
    else
        wypisz_brak "providers" "openssl list -providers nic nie zwrocil"
    fi
else
    wypisz_brak "providers" "nie znaleziono polecenia openssl"
fi

# 3. gnupg
#    Uwaga: na Rocky Linuksie pakiet nazywa sie "gnupg2", ale dostarcza
#    polecenie "gpg" - i wlasnie tego polecenia uzywamy w calym kursie.
sprawdz_narzedzie gpg "gpg" gpg --version

# 4. john the ripper
#    UWAGA: na RHEL 10 tego pakietu NIE MA w zadnym repozytorium, takze w EPEL.
#    Lamanie hasel wykonujemy w rozdziale trzecim na SRV1 (Debian); Rocky sluzy
#    tam wylacznie jako zrodlo skrotu w innym formacie, a skrot mozna przeniesc.
if [ "$RODZINA_RHEL" = tak ]; then
    sprawdz_narzedzie_opcjonalne john "john" \
        "brak w repozytoriach RHEL - lamanie hasel robimy na SRV1" \
        john --list=build-info
else
    sprawdz_narzedzie john "john" john --list=build-info
fi

# 5. hashcat
#    Przelacznik "-V" wypisuje sama wersje i NIE uruchamia silnika
#    obliczeniowego - w maszynie bez karty graficznej to istotna roznica.
if [ "$RODZINA_RHEL" = tak ]; then
    sprawdz_narzedzie_opcjonalne hashcat "hashcat" \
        "brak w repozytoriach RHEL - lamanie hasel robimy na SRV1" \
        hashcat -V
else
    sprawdz_narzedzie hashcat "hashcat" hashcat -V
fi

# 6. tshark (na Rocky Linuksie z pakietu "wireshark-cli")
sprawdz_narzedzie tshark "tshark" tshark -v

# 7. wireguard-tools
sprawdz_narzedzie wg "wg" wg --version

# 8. cryptsetup
sprawdz_narzedzie cryptsetup "cryptsetup" cryptsetup --version

# 9. xxd - swiadomie raportujemy sama obecnosc.
#    Format wersji "xxd" rozni sie miedzy dystrybucjami na tyle, ze porownywanie
#    numerow nie ma tu sensu; liczy sie to, czy polecenie da sie uruchomic.
if mam_polecenie xxd; then
    wypisz_ok "xxd" "obecny"
else
    wypisz_brak "xxd" "nie znaleziono polecenia"
fi

# 10. age
sprawdz_narzedzie age "age" age --version

# 11. curl (na Rocky Linuksie dostarczany przez pakiet "curl-minimal")
sprawdz_narzedzie curl "curl" curl --version

# 12. git
sprawdz_narzedzie git "git" git --version

# 13. testssl.sh - jedyne narzedzie brane prosto od autora projektu.
#     To ta pozycja sluzy w lekcji do testu negatywnego.
if mam_polecenie testssl.sh; then
    WERSJA_TESTSSL=$(pierwsza_wersja testssl.sh --version)
    if [ -z "$WERSJA_TESTSSL" ]; then
        WERSJA_TESTSSL="obecny"
    fi
    wypisz_ok "testssl.sh" "$WERSJA_TESTSSL"
else
    wypisz_brak "testssl.sh" "nie znaleziono polecenia"
fi

# 14. python3 - sprawdzamy nie tylko obecnosc, ale i to, czy dziala modul
#     hashlib, ktorego uzyjemy jako drugiego, niezaleznego swiadka przy skrotach.
if ! mam_polecenie python3; then
    wypisz_brak "python3" "nie znaleziono polecenia"
elif [ "$(python3 -c 'import hashlib; print("ok")' 2>/dev/null)" = "ok" ]; then
    WERSJA_PY=$(pierwsza_wersja python3 --version)
    if [ -z "$WERSJA_PY" ]; then
        WERSJA_PY="obecny"
    fi
    wypisz_ok "python3" "$WERSJA_PY (hashlib dziala)"
else
    wypisz_brak "python3" "polecenie jest, ale modul hashlib nie dziala"
fi

# ---------------------------------------------------------------------------
# Podsumowanie
# ---------------------------------------------------------------------------

RAZEM=$((LICZNIK_OK + LICZNIK_BRAK + LICZNIK_INFO))

echo "---------------------------------------------------------------------------"
if [ "$LICZNIK_INFO" -eq 0 ]; then
    printf ' PODSUMOWANIE: %s pozycji  ->  %s OK, %s BRAK\n' "$RAZEM" "$LICZNIK_OK" "$LICZNIK_BRAK"
else
    printf ' PODSUMOWANIE: %s pozycji  ->  %s OK, %s BRAK, %s nieobowiazkowe\n' \
        "$RAZEM" "$LICZNIK_OK" "$LICZNIK_BRAK" "$LICZNIK_INFO"
fi

if [ "$LICZNIK_BRAK" -eq 0 ]; then
    echo " Wynik: KOMPLET. Warsztat kursu jest na tej maszynie kompletny."
    echo "==========================================================================="
    exit 0
else
    echo " Wynik: NIEKOMPLETNE."
    echo " Co teraz: polecenie instalacyjne dla kazdej pozycji BRAK stoi"
    echo "           w INSTRUKCJI LABORATORYJNEJ do tej lekcji, w zasobach"
    echo "           lekcji na platformie AdminAkademia."
    echo "           Uzupelnij braki i uruchom ten skrypt jeszcze raz."
    echo "==========================================================================="
    exit 1
fi
