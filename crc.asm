global _start

section .rodata
    SYS_WRITE equ 1
    SYS_EXIT  equ 60
    SYS_OPEN  equ 2
    SYS_CLOSE  equ 3
    SYS_READ  equ 0
    SYS_LSEEK  equ 8
    newline equ 10
    STDOUT equ 1
    bufferLength equ 65550          ; > 2^16 - ilosc danych we fragmencie zapisana jest na 2 bajtach
                                    ; dzieki temu wczytany fragment zawsze zmiesci sie w buforze

section .bss
    buffer resb bufferLength
    char resb 1


; r12:r13   dzielna
; r8:r9     dzielnik, czyli wczytany wielomian z dodana 1 na przodzie
; rdi       deskryptor pliku
; rbx       adres wczytywanego bajtu w wielomianie
;           po zamianie wielomianu oznacza dlugosc reszty
; rcx       cl do porownywania kodu ASCII z 0 i 1
; r10       licznik bitow do 8
; r14       ilosc danych w segmencie
; r15       licznik wczytanych danych w segmencie
;           Gdy skoncza sie dane sluzy jako licznik
;           do przetworzenia pozostalych danych wczytanych do r12:r13
; rax       Przechowuje bezwzgledny adres fragmentu od poczatku pliku
; Wywolania funkcji systemowych
; rsi
; rax
; rdx


section .text

_start:
    ; Sprawdzenie ilosci argumentow
    mov rdi, [rsp]              ; pierwsza wartosc na stosie trzyma ilosc argumentow
    cmp rdi, 3                  ; powinny byc 3 (nazwa programu, nazwa pliku, wielomian)
    jne error                   ; jesli nie ma dokladnie trzech to blad

    ; wczytanie wielomianu
    mov rbx, [rsp + 24]         ; adres zapisu wielomianu w ASCII
    dec rbx
    xor r12, r12                ; rejestr do trzymania starszej czesci wielomianu
    xor r13, r13                ; rejestr do trzymania mlodszej czesci wielomianu

    inc r13                     ; do wielomianu z przodu dopisujemy jeden

    ; pusty wielomian
    mov cl, byte [rbx + 1]      ; Wczytaj następny znak
    cmp cl, 0                   ; Sprawdz czy to koniec zapisu wielomianu
    je error

characters_conversion_loop:
    inc rbx                     ; Zwiekszenie dlugosci wczytanego wielomianu
    mov cl, byte [rbx]          ; Wczytaj następny znak
    cmp cl, 0                   ; Sprawdz czy to koniec zapisu wielomianu
    je conversion_done          ; jesli tak, skoncz konwertowanie

                                ; w przeciwnym wypadku
                                ; Zwolnij miejsce dla nastepnego bitu
    shl r13, 1                  ; Przesuniecie wartosci w r12:r13 o jeden bit w lewo
    rcl r12, 1
    cmp cl, '1'                 ; Sprawdz czy znak to '1'
    jne check_if_zero           ; jesli nie to sprawdz czy zero
    or r13, 1                   ; jesli tak to ustaw najmniej znaczacy bit na 1
    jmp characters_conversion_loop  ; Wczytaj kolejny znak

    check_if_zero:              ; Sprawdzy czy znak to '0'
    cmp cl, '0'
    jne error                   ; Jesli nie to blad
    jmp characters_conversion_loop  ; Wczytaj kolejny znak
conversion_done:
    sub rbx, [rsp + 24]         ; dlugosc wielomianu bez dodanej jedynki z przodu
                                ; taka tez jest dlugosc reszty

shift_left:                     ; Przesuniecie wielomianu, tak aby w MSB bylo jeden
    cmp r12, 0
    jl open_file
    shl r13, 1                  ; Przesuniecie wartosci w r12:r13 o jeden bit w lewo
    rcl r12, 1
    jmp shift_left


open_file:
    mov rdi, [rsp+16]           ; nazwa pliku
    xor rsi, rsi                ; Otwarcie w trybie czytania
    mov rax, SYS_OPEN
    syscall

    cmp rax, 0                  ; Jesli rax == 0
    js error                    ; to blad
    mov rdi, rax                ; Zapisanie deskryptora pliku do rdi

    call read                   ; Wczytanie danych do bufora


    ; Przygotowanie do wykonania algorytmu CRC
    xor r10d, r10d              ; licznik bitow do 8,
                                ; gdyz co 8 bitow pobieramy nastepne dane do r9b
    xor r14, r14                ; Zerujemy r14, gdyz adresowanie wymaga 64 bitowych rejestrow
    mov r14w, [buffer]          ; Wczytanie dlugosci danych w segmencie
    xor r15, r15                ; licznik wczytanych bajtow z danego fragmentu
    xor rax, rax                ; zerowanie
crc:
    cmp r10d, 8                 ; Sprawdzenie czy wczytano 8 bitow
    jne xoring                  ; Jesli nie to odpowiednio xoruj dane

    cmp r14w, r15w              ; Sprawdz czy skonczyly sie dane we fragmencie
    jne load_8_bits_to_r9       ; Jesli nie to pobierz kolejne 8 bitow z bufora

new_buffer:
                                ; Jesli sie skonczyly to wczytaj offset do nastepnego framentu
    mov r15d, [buffer + r14 + 2]; r15d trzyma offset do nastepnego fragmentu
                                ; Jesli ilosc danych we fragmencie
    add r14d, 6                 ;  + ilosc bajtow sluzacych do zapisu ilosci danych we fragmencie i do zapisu offsetu
    add r14d, r15d              ;  + offset do nastepnego fragmentu
    cmp r14d, 0                 ; rowna sie zero to oznacza koniec pliku
    jz end_of_file              ; offset wskazuje na poczatek swojego fragmentu

    add r14d, eax               ; Do wzglednego przesuniecia wzgledem poczatku fragmentu
    mov esi, r14d               ; dodajemy bezwzgledny adres poczatku fragmentu od poczatku pliku
    mov rdx, 0                  ; bezwzgledne adresowanie
    mov rax, SYS_LSEEK          ; Przesuniecie wskaznika w pliku
    syscall

    cmp rax, 0                  ; Jesli nie udalo sie wczytac z pliku
    je close_file               ; to zamknij plik i zakoncz program z bledem

    mov r14, rax                ; Przechowanie bezwzlednego adres poczatku fragmentu od poczatku pliku
    call read                   ; Wczytanie danych do bufora (modyfikuje rax)
    mov rax, r14                ; Odtworznie adresu

    xor r14, r14
    mov r14w, [buffer]          ; Wczytanie ilosci danych we fragmencie
    xor r15, r15                ; Wyzerowanie licznika wczytanych bajtow we fragmencie

    cmp r14w, 0                 ; Pusta sekcja danych
    je new_buffer               ; Skok do czytania offsetu

load_8_bits_to_r9:
    mov r9b, [buffer + 2 + r15] ; Dane zaczynaja sie 2 bajty od poczatku sekcji,
                                ; gdyz pierwsze 2 bajty oznaczaja ilosc danych we fragmencie
    xor r10d, r10d              ; Wyzerowanie licznika do 8
    inc r15w                    ; Zwiekszenie liczinka wczytanych bajtow danych

    xoring:                     ; Xorowanie jesli jeden jest MSB w r12
    call xor_                   ; i przesuniecie r12:r13 o jeden bit w lewo

    inc r10d                    ; Zwiekszenie licznika bitow
    jmp crc                     ; Ponowne wykonanie procedury


; Skok do end_of_file jest wtedy, gdy przesunieto dane o 8 bitow w lewo i  skonczyly sie dane w pliku.
end_of_file:
    xor r15w, r15w
loop_xoring_end:                ; Xorowanie pozostalych danych
    cmp r15w, 120               ; 128 - 8
    je print_remainder          ; Jesli skonczyly sie dane wydrukuj reszte
    call xor_                   ; Jesli nie wykonuj xorowanie takie jak w crc
    inc r15w                    ; Zwieksz licznik przetworzonych bitow
    jmp loop_xoring_end


    ; Przygotowanie do petli drukowania znakow
    print_remainder:            ; Drukowanie reszty z bufora
    mov rdi, 1                  ; Zapis '0' i '1' w ASCII zajmuje jeden bajt
    mov rax, SYS_WRITE          ; Ustawienie wywolania systemowego na pisanie
    mov rdx, STDOUT             ; Ustawienie deskryptora pliku
    xor r14, r14
    xor r15b, r15b              ; Licznik przetworzonych znakow
    xor rsi, rsi

    loop_print_remainder:
    cmp r15b, bl                ; Sprawdzenie czy licznik przetworzonych znakow rowna sie dlugosci reszty
    je correct_end              ; Jesli tak zakoncz wykonywanie programu
    xor r14b, r14b
    shl r9, 1                   ; Przsuniecie r14:r8:r9 w lewo
    rcl r8, 1                   ; Dzieki temu MSB r8 znajduje sie w LSB r14
    rcl r14b, 1
    cmp r14b, 1                 ; Sprawdzenie czy jest to 1
    jne zero                    ; Jesli nie to jest to 0

    mov [char], byte '1'        ; Jesli tak zaladuj '0' to wydrukowania
    jmp print

    zero:
    mov [char], byte '0'        ; Zaladuj '0' to wydrukowania

    print:
    mov rsi, char
    syscall

    cmp rax, 0                  ; Jesli nie udalo wydrukowac
    je close_file               ; to zamknij plik i zakoncz program z bledem

    inc r15b                    ; Zwieksz licznik wydrukowanych bitow reszty
    jmp loop_print_remainder


correct_end:
    mov [char], byte newline    ; Druk nowej linii
    mov rsi, char
    syscall

    mov rax, SYS_CLOSE          ; Zamkniecie pliku
    syscall

    mov rax, SYS_EXIT           ; Zakonczenie programu
    xor rdi, rdi
    mov rdi, 0                  ; bez bledu
    syscall

close_file:
    mov rax, SYS_CLOSE          ; Zamkniecie pliku
    syscall

error:
    mov rax, SYS_EXIT
    mov rdi, 1                  ; Exit code 1
    syscall

read:
    mov rsi, buffer             ; Wskazanie bufora do wczytania danych
    mov rdx, bufferLength       ; Ilosc bajtow do wczytania
    mov rax, SYS_READ
    syscall                     ; Wczytanie danych do bufora

    cmp rax, 0                  ; Jesli nie udalo sie wczytac z pliku
    je close_file               ; to zamknij plik i zakoncz program z bledem

    ret

xor_:
    cmp r8, 0
    jge .shift_left             ; Jesli MSB to 0 wylacznie przesun r8:r9 w lewo o 1 bit
    xor r8, r12                 ; Jesli MSB to 1 wykonaj xor dzielna r8:r9, dzielnik r12:r13
    xor r9, r13
    .shift_left:
    shl r9, 1
    rcl r8, 1

    ret