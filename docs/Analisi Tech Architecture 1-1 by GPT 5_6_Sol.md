## Giudizio netto

È una proposta architetturale buona, nettamente sopra la media dei PRD, ma non ancora pronta per essere trasformata direttamente in codice.

Autorizzerei alcuni spike tecnici e la revisione degli ADR critici.

Il problema di fondo è che il documento confonde talvolta:

- una buona intenzione;
- un meccanismo plausibile;
- una garanzia assoluta.

Le prime due ci sono quasi sempre. Alcune garanzie, invece, non sono tecnicamente sostenibili.

## Cosa funziona molto bene

Le decisioni portanti sono sensate:

- Applicazione nativa macOS, locale e senza backend: perfettamente coerente con il prodotto.
- Distinzione fra dati derivati e dati autorali: è la decisione più importante del documento ed è corretta.
- Eventi del filesystem trattati come suggerimenti e riconciliazione come fonte di verità: ottimo.
- Elaborazioni lazy, code limitate, priorità alle celle visibili e attenzione esplicita alla memoria: raro vedere questo rischio riconosciuto già nel PRD.
- `NSCollectionView` per la griglia e SwiftUI altrove: scelta pragmatica.
- Dry-run, journal e Cestino per le operazioni massive: direzione corretta.
- ADR che dichiarano conseguenze e non soltanto tecnologie: buon segno di maturità.

Non vedo “architecture astronautics” nelle scelte fondamentali. Vedo però una tendenza a descrivere come risolti problemi che sono ancora solo impostati correttamente.

## I problemi seri

### 1. SQLite non è realmente una cache ricostruibile

`IndexStore` contiene:

- dati derivati;
- copia dei giudizi;
- giudizi non ancora scritti o non scrivibili nei sidecar;
- journal persistente delle operazioni.

Gli ultimi due non sono ricostruibili. Se si elimina SQLite, si perde almeno la cronologia di undo e potenzialmente il solo esemplare di alcuni giudizi. Quindi l’affermazione “indice integralmente ricostruibile” è falsa rispetto all’architettura descritta.

Separerei fisicamente o almeno logicamente:

- `DerivedCache`: eliminabile;
- `DurableState`: journal, operazioni incomplete, scritture sidecar pendenti, preferenze autorali.

Anche la risoluzione “vince la fonte modificata più recentemente” è troppo fragile. Serve uno stato esplicito: `clean`, `pendingWrite`, `writeFailed`, `externalConflict`, con revisione, provenienza e ultima versione XMP osservata.

### 2. Immagine e sidecar non possono essere “un’unità indivisibile”

APFS non offre una transazione atomica che sposti immagine, sidecar e centinaia di altri file come un unico commit. Un crash può sempre avvenire fra due operazioni.

Il journal non rende l’operazione atomica: la rende, se progettato bene, **recuperabile**.

`FileOps` dovrebbe essere descritto come una macchina a stati con write-ahead log:

1. registra piano e precondizioni;
2. marca il lotto `prepared`;
3. esegue passi idempotenti;
4. registra ogni passo completato;
5. al riavvio riprende o compensa.

Vanno inoltre ricontrollate le precondizioni dopo il dry-run, perché tra anteprima e conferma il filesystem può cambiare.

Anche “ripristino garantito dal Cestino” è troppo forte: macOS restituisce la posizione assunta nel Cestino, ma non garantisce che l’elemento resti lì o sia sempre ripristinabile; l’utente può svuotarlo o modificarlo. [FileManager documenta lo spostamento e la resulting URL, non una garanzia permanente di undo](https://developer.apple.com/documentation/foundation/filemanager/trashitem%28at%3Aresultingitemurl%3A%29?changes=latest_major&language=objc).

### 3. I giudizi non possono seguire sempre gli spostamenti esterni

Questa promessa è materialmente irrealizzabile:

> I giudizi sopravvivono agli spostamenti fatti fuori dall’app.

Se nel Finder l’utente sposta soltanto `foto.jpg`, il Finder non sa che `foto.xmp` è collegato e lascia il sidecar indietro. Inoltre l’app osserva solo la cartella aperta: non può sapere dove sia finita l’immagine.

Anche il fallback tramite hash ha problemi:

- il rilevamento duplicati calcola SHA-256 completo solo su collisione, quindi l’hash non è già disponibile gratuitamente per ogni file;
- due duplicati esatti hanno lo stesso hash;
- un salvataggio esterno cambia il contenuto;
- calcolare eagerly l’hash di 50.000 immagini confligge con le promesse di reattività.

Serve una matrice esplicita dei casi supportati: rinomina nella cartella osservata, spostamento immagine+sidecar, spostamento su altro volume, copia, sostituzione atomica, modifica del contenuto, sidecar orfano. Negli altri casi si deve parlare di “recupero best effort”, non di garanzia.

Userei inoltre `fileResourceIdentifier`, volume UUID e bookmark come identità primaria, non una formulazione generica `volume + inode`; Foundation espone appositamente un [identificatore univoco della risorsa](https://developer.apple.com/documentation/foundation/urlresourcekey?changes=_5).

### 4. FSEvents è impostato bene, ma sottospecificato

La riconciliazione è corretta. Manca però la parte difficile:

- event ID associato al volume UUID;
- volume smontato o ripristinato;
- event ID eliminati o riavvolti;
- `RootChanged`;
- eventi persi;
- comportamento su SMB, iCloud e File Provider;
- raffiche continue che non raggiungono mai la “finestra di quiete”.

Apple raccomanda stream per-disk quando la persistenza conta e avverte che gli ID possono essere eliminati, riavvolti o entrare in conflitto. Inoltre gli eventi file-level sono deliberatamente molto più numerosi. [FSEvents Programming Guide](https://developer.apple.com/library/archive/documentation/Darwin/Conceptual/FSEvents_ProgGuide/UsingtheFSEventsFramework/UsingtheFSEventsFramework.html), [file-level events](https://developer.apple.com/documentation/coreservices/kfseventstreamcreateflagfileevents).

Aggiungerei un tempo massimo di riconciliazione oltre al debounce, altrimenti un’importazione continua può rimandarla indefinitamente.

### 5. La scrittura XMP ha rischi di concorrenza e interoperabilità

“Rileggo, modifico i campi noti e riscrivo gli altri invariati” non evita che un’altra applicazione modifichi il sidecar tra lettura e sostituzione. Serve almeno controllo ottimistico della versione osservata e merge/conflitto esplicito. `NSFileCoordinator` è il meccanismo di sistema pensato per coordinare accessi tra processi, pur non creando una transazione. [Documentazione Apple](https://developer.apple.com/documentation/foundation/nsfilecoordinator?changes=_7).

Vanno poi definiti:

- convenzione del nome: `foto.xmp` o `foto.jpg.xmp`;
- collisione fra `foto.jpg` e `foto.heic`;
- rappresentazione interoperabile di “da scartare”;
- semantica di `xmp:Label`, che non è uniforme fra tutti gli strumenti;
- test reali di round-trip con Bridge, Lightroom, darktable e digiKam.

Dire “XMP standard” non basta a garantire interoperabilità.

### 6. Vision non offre direttamente “occhi aperti/chiusi”

Vision fornisce landmark degli occhi, non un classificatore documentato dello stato aperto/chiuso. La conclusione deve essere ottenuta con un’euristica o un modello proprio e calibrata su occhiali, profilo, occlusioni e risoluzioni basse. [VNDetectFaceLandmarksRequest](https://developer.apple.com/documentation/vision/vndetectfacelandmarksrequest?language=objc).

Il face-capture quality score è inoltre olistico: incorpora illuminazione, nitidezza, posa, centratura e altro. Può quindi duplicare criteri che la pipeline dichiara separati. [Face capture quality](https://developer.apple.com/documentation/vision/vndetectfacecapturequalityrequest?language=objc).

Bisogna versionare nell’indice:

- revisione Vision;
- versione del modello;
- preprocessing;
- algoritmo e soglie.

Altrimenti gli score in cache diventano semanticamente obsoleti dopo un aggiornamento.

## Due rischi trasversali

Lo scheduler unico può facilmente diventare un “god actor”. Dimensioni in pixel non bastano a stimare memoria di Vision, Core ML, texture GPU, HEIC multipagina o risorse QuickLook. Userei code separate per I/O, decode, Vision/ML e database, coordinate da un budget comune con misurazioni reali. Inoltre cancellare immediatamente ogni cella appena uscita dallo schermo può causare thrashing: serve una finestra di prefetch con isteresi.

Infine, questo non è un MVP nel senso comunemente usato. È contemporaneamente browser performante, sistema di metadata, motore transazionale di file operations, interoperabilità XMP, duplicate finder, pipeline ML, editor e applicazione accessibile. È più vicino a una **v1 professionale**. Il fatto che il costo sia “dichiarato e accettato” non elimina il rischio di integrazione.

## Cosa chiederei prima di approvare lo sviluppo

Prima del full build pretenderei quattro spike:

1. 50.000 file, griglia e memoria su dataset e hardware dichiarati.
2. Matrice FSEvents su APFS, volume esterno, iCloud e SMB.
3. Round-trip XMP con strumenti reali e conflitti concorrenti.
4. Crash injection in ogni punto di un lotto FileOps, seguito da recovery.

E riscriverei ADR-003, 007, 011, 012 e 013 eliminando parole come “indivisibile”, “garantito” e “sempre” dove il sistema può offrire soltanto recovery o best effort.

In sintesi: **ottima impostazione, buone antenne architetturali, ma eccesso di fiducia nelle garanzie del filesystem e dei sidecar**. L’architetto sa quali sono i problemi difficili; deve ancora dimostrare di averli davvero chiusi.