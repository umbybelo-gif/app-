# Ciak — archivio video per content creator

App iOS **nativa e locale** per girare, organizzare ed esportare i video di lavoro.
Niente account, niente cloud, niente rete: tutto resta sul tuo iPhone.

Struttura: **Progetto → Sketch → Ciak (clip)**.

---

## Perché nativa e non una web app

Una web app (PWA) in Safari non può fare quasi nulla di ciò che ti serve:

| Cosa ti serve | Web app | App nativa (questa) |
|---|---|---|
| 4K a 30/60 fps | ❌ risoluzione decisa da Safari | ✅ formato del sensore scelto a mano |
| Stabilizzazione cinematica | ❌ non esposta | ✅ la più forte supportata dal telefono |
| ProRes / HDR 10 bit / Apple Log | ❌ | ✅ dove l'iPhone lo permette |
| Fuoco, ISO, otturatore, bianco manuali | ❌ | ✅ |
| Face ID | ❌ (solo passkey, altra cosa) | ✅ |
| File video pesanti in locale | ❌ quota di Safari, cancellabile dal sistema | ✅ sandbox dell'app |

Per questo il progetto è un'app SwiftUI + AVFoundation.

---

## Requisiti

- Un **Mac** con **Xcode 16 o successivo** (serve solo per installare l'app; poi il Mac non serve più).
- Un **iPhone con iOS 17 o successivo**, collegato via cavo la prima volta.
- Un **Apple ID** qualunque. Non serve l'abbonamento da 99 €/anno.

---

## Installazione sul tuo iPhone

1. Scarica questa cartella sul Mac e apri **`Ciak.xcodeproj`**.
2. Nella colonna di sinistra seleziona il progetto **Ciak** → scheda **Signing & Capabilities**.
3. Spunta **Automatically manage signing** e scegli il tuo **Team** (il tuo Apple ID: `Add an Account…` se non c'è).
4. Cambia il **Bundle Identifier** in qualcosa di unico tuo, ad esempio `com.tuonome.ciak`.
   Con un Apple ID gratuito è obbligatorio, altrimenti la firma fallisce.
5. Collega l'iPhone, selezionalo nella barra in alto al posto del simulatore e premi **▶︎ (Run)**.
6. Sull'iPhone: **Impostazioni › Generali › VPN e gestione dispositivo** → tocca il tuo profilo → **Autorizza**.

### Nota importante sulla scadenza

- **Apple ID gratuito**: l'app smette di aprirsi dopo **7 giorni**. Per rinnovarla ricollega
  l'iPhone al Mac e premi di nuovo **Run** — *i video e i progetti restano al loro posto*.
- **Apple Developer Program (99 €/anno)**: l'app dura **1 anno** e non devi ricollegare nulla.
  Se la usi per lavoro, conviene.

---

## Cosa fa

### Organizzazione
- **Progetti** con nome, colore, note, archiviazione.
- **Sketch** dentro ogni progetto, con copione/note e stato "completato".
- **Ciak** numerati automaticamente (Ciak 1, Ciak 2, …), con nota per ciascuno e stella "buona"
  per marcare la ripresa da usare in montaggio.
- Ricerca su progetti e sketch, spostamento di clip da uno sketch all'altro, riordino.

### Ripresa
- Sceglie da solo il **formato migliore del sensore** che soddisfa le tue impostazioni
  (non usa i preset generici, quindi 4K60 e HDR arrivano davvero).
- **Stabilizzazione**: prova nell'ordine cinematica potenziata → cinematica estesa → cinematica →
  standard, e ti mostra sempre **quale è stata applicata davvero**.
- **Codec**: HEVC, H.264, ProRes (dove supportato).
- **Colore**: SDR, HDR 10 bit (HLG), Apple Log (iPhone 15 Pro e successivi).
- **Audio**: stereo e riduzione del rumore del vento dove il sistema li offre.
- **Controlli manuali**: fuoco, compensazione EV, ISO + otturatore, temperatura colore.
- Zoom continuo con le fermate reali degli obiettivi (0.5× / 1× / 2× / 3× / 5×), tocca per mettere
  a fuoco, torcia, griglia dei terzi, orizzonte gestito da `RotationCoordinator`.
- Controlla lo spazio libero prima di far partire una registrazione.

### Esportazione
- **Condividi** una clip singola (AirDrop, File, Mail, WhatsApp…).
- **Salva in Foto** una o più clip.
- **Esporta un intero progetto o sketch in .zip**, con i file rinominati in modo leggibile
  (`Sketch_Ciak-03_BUONA.mov`), le cartelle divise per sketch e un `NOTE.txt` con durate,
  dati tecnici e le tue annotazioni.
- **Cavo**: l'app espone i suoi file, quindi puoi prenderli da **Finder › iPhone › File › Ciak**
  senza passare da nessuna app.

### Sicurezza
- Password dell'app obbligatoria al primo avvio.
- Sblocco con **Face ID / Touch ID** (attivabile e disattivabile).
- Blocco automatico configurabile (subito / 1 / 5 / 15 minuti).
- Schermo oscurato nel selettore app, così le anteprime non mostrano i tuoi video.
- La password **non viene salvata**: nel portachiavi finisce solo un hash PBKDF2-SHA256
  (210.000 iterazioni, sale casuale), con accessibilità limitata a questo dispositivo.

> ⚠️ Se dimentichi la password non c'è recupero. L'unico modo di rientrare è disinstallare
> l'app, e questo cancella i video. Esporta con regolarità ciò a cui tieni.

---

## Struttura del codice

```
Ciak/
  CiakApp.swift            avvio e instradamento blocco/sblocco
  Auth/                    password (PBKDF2 + Keychain), Face ID, schermate di blocco
  Model/                   Project / Sketch / Clip e l'archivio su disco (JSON + file)
  Camera/                  sessione AVFoundation, impostazioni, controlli manuali, UI di ripresa
  Library/                 elenco progetti, sketch, dettaglio clip, impostazioni
  Export/                  condivisione, salvataggio in Foto, archivio .zip
  Common/                  miniature e componenti riutilizzabili
```

I metadati stanno in `Documents/library.json`, i video in `Documents/Media/`,
le miniature in `Documents/Thumbs/`.

---

## Limiti da conoscere

Sono limiti di iOS, non del codice: nessuna app di terze parti può superarli.

- **Modalità Azione** e **Modalità Cinema** sono esclusive dell'app Fotocamera di Apple:
  AVFoundation non le espone. La stabilizzazione "cinematica potenziata" è l'equivalente
  più vicino disponibile.
- Alcune combinazioni si escludono a vicenda (per esempio ProRes a 4K60, o stabilizzazione
  massima ad alti frame rate). L'app non finge: sceglie il formato più vicino possibile,
  corregge le impostazioni e ti mostra quello che sta davvero usando.
- Il bitrate di HEVC/H.264 lo decide il sistema. Se vuoi il controllo totale sulla qualità,
  usa ProRes.
- iOS interrompe la registrazione se l'app va in background: è il comportamento previsto
  per tutte le app fotocamera.

---

## Se qualcosa non compila

- **"Signing for Ciak requires a development team"** → punto 3 dell'installazione.
- **"Failed to register bundle identifier"** → il Bundle Identifier è già usato da qualcun altro:
  cambialo (punto 4).
- Errori su `multichannelAudioMode` o `windNoiseRemoval`: sono impostati in modo dinamico
  proprio per evitarlo; se il tuo Xcode protesta comunque, puoi cancellare il corpo del metodo
  `applyAudioEnhancements` in `Ciak/Camera/CameraController.swift` — perdi solo stereo e
  antivento, il resto funziona.
