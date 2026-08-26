# iMAGE Surfer - Product Requirements Document

**Autore:** ARchetipo
**Data:** 2026-08-26
**Versione:** 1.3

> **Revisione 1.3** — Terza e ultima revisione architetturale sulla carta. Non corregge decisioni sbagliate ma **frasi che promettevano più di quanto il meccanismo sottostante faccia** — la stessa classe di difetto delle due revisioni precedenti, ormai riconosciuta come motivo ricorrente e messa sotto sorveglianza esplicita. Modifiche sostanziali: contratto operativo di durabilità e **invariante direzionale di autorità** tra stato durevole, sidecar e cache (ADR-003); cinque esiti del recupero al posto di due, e distinzione tra errore locale e sistemico (ADR-007); budget su **stime conservative calibrate su misure reali**, perché ammettere lavoro prima di eseguirlo richiede necessariamente una stima (ADR-009); riconciliazione **avviata** entro il tempo massimo, non completata, con stati di freschezza della vista visibili all'utente (ADR-012); coordinamento tra processi riconosciuto come **cooperativo e non impositivo**, con verifica dopo la sostituzione e recupero da scritture non coordinate (ADR-013); correzione di un errore propagato da tre versioni sul rapporto tra sandbox e distribuzione (ADR-005); e un modello di minaccia per la decodifica di **dati non fidati** in un processo con pieni privilegi (ADR-016). Lo scope dell'MVP non è stato ridotto. Con questa versione le revisioni sulla carta si chiudono: le domande rimaste si chiudono misurando, in Tappa 0.

---

## Elevator Pitch

<!-- archetipo:prd section=elevator_pitch required=true -->

> Il Finder di macOS è un gestore di file che tollera le immagini. iMAGE Surfer è l'opposto: tratta una cartella come un rullino da lavorare, non come un elenco di file. Apri qualsiasi cartella, vedi solo le immagini, le giudichi grandi sullo schermo muovendoti con le sole frecce, leggi i metadati senza aprire nulla, e quando ti trovi davanti a otto scatti quasi identici l'app ti dice quali tenere e perché. Nessuna importazione, nessun catalogo, nessun lock-in: le tue foto restano dove sono, e i giudizi che dai vengono scritti accanto a loro.
>
> Per **chi accumula migliaia di immagini in cartelle su macOS e le deve selezionare, rinominare e riorganizzare a mano**, che ha il problema di **usare un file manager generalista per un lavoro squisitamente visivo — anteprime minuscole, metadati sepolti in Get Info, navigazione che richiede il mouse e zero aiuto nella scelta tra scatti simili**, **iMAGE Surfer** è un **browser e banco di triage per immagini, nativo macOS** che **permette di vedere, giudicare e riorganizzare migliaia di foto senza mai lasciare la tastiera, con selezione assistita da AI che gira interamente in locale**. A differenza del **Finder (e dei cataloghi tipo Lightroom o Foto di macOS)**, il nostro prodotto **unisce la velocità di uno strumento professionale di triage all'assenza totale di importazione: la cartella sul disco resta l'unica fonte di verità, i giudizi sono scritti in un formato che altri strumenti sanno leggere, e ogni operazione massiva è mostrata in anteprima e recuperabile**.

---

## Vision

<!-- archetipo:prd section=vision required=true -->

Rendere il lavoro su un insieme di immagini — guardarle, sceglierle, scartarle, rinominarle, ordinarle — un'attività fluida, veloce e a tastiera, sfruttando fino in fondo ciò che macOS già offre: decodifica accelerata di ogni formato fotografico, visione artificiale sul Neural Engine, Cestino reversibile, notifiche del filesystem. Tutto in locale, senza cloud, senza account, senza spedire una sola immagine fuori dal Mac.

L'obiettivo di lungo periodo non è diventare un editor fotografico né un catalogo: è diventare **il livello di curation che manca tra il filesystem e gli strumenti di editing**. Il posto dove decidi *cosa merita di esistere* e *dove deve stare*, prima di aprire qualunque altra cosa.

### Differenziatore di Prodotto

Tre scelte, tenute insieme, che nessuna alternativa attuale combina:

1. **La cartella è la fonte di verità — e il lavoro di giudizio viene scritto lì dentro.** L'app non importa, non sposta a tua insaputa, non crea una libreria proprietaria. L'indice locale è una cache di dati *ricalcolabili*, e cancellarlo non fa perdere nulla. Ciò che *tu* hai deciso — stelle, marcature — non è ricalcolabile, quindi non vive in una cache: viene scritto accanto all'immagine in un sidecar standard che altri strumenti fotografici sanno leggere. Se domani disinstalli iMAGE Surfer, quel lavoro resta nella cartella. Questo è l'opposto del modello Lightroom/Foto, dove il lavoro resta nel catalogo. **Con un limite dichiarato, non nascosto:** un sidecar è un file separato, e se lo si separa dall'immagine fuori dall'app il collegamento può andare perso. I casi in cui l'associazione regge, quelli in cui viene recuperata a tentativo e quelli in cui non è recuperabile sono elencati uno per uno nei requisiti, invece di essere coperti dalla parola "sempre".
2. **Il triage a tastiera come interazione primaria, non come scorciatoia.** Frecce per muoversi, spazio per l'anteprima grande, un tasto per il rating, un tasto per marcare da scartare. Il mouse è opzionale, non necessario.
3. **L'AI argomenta, non decreta.** Il sistema non dice "questa è la più bella": raggruppa gli scatti quasi identici, li mette a confronto e mostra le ragioni misurabili di una proposta. La decisione finale, e l'unico dito sul grilletto, restano dell'utente. E le ragioni devono essere davvero distinte tra loro: dove due criteri si sovrappongono, la sovrapposizione va dichiarata invece di essere presentata come conferma indipendente.

Sotto le tre scelte c'è una regola di scrittura che vale per tutto il documento e che tre revisioni hanno reso esplicita: **un meccanismo cooperativo o best-effort non viene mai descritto come se fosse impositivo**. Il filesystem non offre transazioni su più file, un sidecar può essere separato dalla sua immagine, il coordinamento tra applicazioni funziona solo con chi vi partecipa. Dove il sistema può soltanto tentare, il documento dice che tenta — e dice cosa fa quando fallisce.

---

## User Personas

<!-- archetipo:prd section=user_personas required=true -->

### Persona 1: Guidalberto - il curatore di cartelle

**Ruolo:** Professionista tecnico (sviluppo/consulenza), fotografo per passione, unico proprietario e amministratore del proprio Mac
**Età:** 35-50 | **Background:** Utente macOS avanzato da anni. Scatta con smartphone e con una mirrorless, scarica le schede a mano in cartelle organizzate per anno/evento. Ha volutamente rifiutato Lightroom e la libreria di Foto: non vuole che un software si metta in mezzo tra lui e i suoi file.

**Obiettivi:**
- Passare da 300 scatti scaricati a 40 scatti tenuti in pochi minuti, non in una serata.
- Dare ai file nomi che avranno ancora senso tra dieci anni, senza rinominare a mano.
- Sapere che una cartella "fatta" è davvero pulita: nessun duplicato, nessuno scarto rimasto dentro.
- Non dipendere da nessun servizio cloud e da nessun formato proprietario — nemmeno dal nostro.

**Punti di dolore:**
- In una cartella vede `.DS_Store`, PDF, ZIP e sidecar mescolati alle foto: deve filtrare a occhio ogni volta.
- Le anteprime del Finder sono troppo piccole per capire se uno scatto è a fuoco: deve aprire l'immagine in un'altra app, guardarla, chiuderla, e ripetere. Decine di volte.
- Non può scorrere le anteprime con le frecce: ogni passaggio richiede mouse o trackpad.
- Per leggere ISO, obiettivo o ora di scatto serve tasto destro → Get Info, una finestra per immagine.
- Davanti a otto scatti dello stesso momento nessuno strumento lo aiuta: sceglie a intuito, oppure — più spesso — non sceglie e tiene tutto.
- Riorganizza le cartelle nel Finder senza pensarci: vuole sapere in anticipo, e con precisione, cosa uno strumento sa seguire e cosa no.

**Comportamenti e strumenti:**
Finder, Anteprima, QuickLook, occasionalmente un editor per un ritaglio. Lavora a tastiera dove può. Diffida delle scelte automatiche irreversibili, ma si fida di uno strumento che gli mostra prima cosa farà — e che gli dice dove si ferma.

**Motivazioni:** Recuperare tempo su un lavoro ripetitivo che oggi lo frustra; avere un archivio di cui va fiero e di cui è padrone.
**Competenza tecnica:** Alta. Sa cosa sono EXIF, hash, spazio colore, sidecar. Non ha bisogno che gli si semplifichi la realtà, ha bisogno che gli si risparmino i clic.

#### Percorso Utente - Guidalberto

| Fase | Azione | Pensiero | Emozione | Opportunità |
|---|---|---|---|---|
| Consapevolezza | Dopo l'ennesima serata a scremare una cartella nel Finder, cerca "image browser macOS keyboard" | "Non può essere che nel 2026 io stia ancora aprendo e chiudendo file uno per uno" | Frustrazione, stanchezza | Comunicare il prodotto sulla frustrazione esatta, non su una lista di funzioni |
| Considerazione | Valuta Lightroom, Photo Mechanic, Foto di macOS | "Tutti vogliono importare le mie foto in una loro libreria. Io voglio solo *guardare* la mia cartella" | Diffidenza | Dichiarare in prima riga: nessuna importazione, la cartella resta la fonte di verità, i giudizi vengono scritti nella cartella |
| Primo utilizzo | Trascina una cartella con 800 foto sull'app | "Vediamo quanto ci mette prima di mostrarmi qualcosa. E vediamo cosa mi chiede di firmare" | Curiosità mista a scetticismo | Prima anteprima visibile in meno di un secondo; nessun account, nessun setup, nessun permesso chiesto prima del gesto che lo richiede |
| Uso regolare | Ogni scarico di schede finisce nell'app: triage a frecce, rating, gruppi di simili, rinomina massiva, smistamento in sottocartelle | "Quaranta minuti di lavoro diventati cinque" | Fiducia, controllo | Ricordare le cartelle recenti e i pattern usati; rendere ogni operazione massiva recuperabile e dichiararne i limiti |
| Advocacy | Lo mostra a un amico fotografo e gli manda il `.dmg` | "Questo risolve un problema che abbiamo tutti e nessuno risolve" | Soddisfazione | Il `.dmg` notarizzato è già un canale di distribuzione a terzi: curarne l'esperienza di installazione fin dall'MVP |

---

### Persona 2: Adalgisa - la selezionatrice sotto scadenza

**Ruolo:** Content/social manager in una PMI; riceve materiale fotografico da fotografi esterni e colleghi
**Età:** 25-40 | **Background:** Ogni settimana le arriva una cartella condivisa con 200-500 immagini di un evento o di un prodotto, prodotte da persone e apparecchi che non controlla e passate per canali che non sceglie. Deve consegnare pochi scatti selezionati, nominati secondo la convenzione aziendale e ordinati in sottocartelle per canale.

**Obiettivi:**
- Ridurre 400 immagini a 12 buone, oggi, non domani.
- Rispettare la convenzione di naming aziendale senza rinominare un file per volta.
- Non consegnare mai due volte la stessa foto con nomi diversi.
- Far vedere al fotografo quali scatti ha scelto, senza scrivergli un elenco a mano.

**Punti di dolore:**
- Riceve raffiche: dieci scatti dello stesso sorriso, e deve capire in quale gli occhi sono aperti guardando anteprime di 128 pixel.
- Rinomina a mano, sbaglia, e il conteggio progressivo salta.
- Trova quasi-duplicati e duplicati esatti mescolati e non ha modo di distinguerli.
- Lavora spesso su cartelle condivise di rete o sincronizzate: file che sembrano esserci ma non sono ancora scaricati, e strumenti che se ne accorgono tardi.
- **Il materiale non è suo e non è controllato**: file troncati, formati inattesi, immagini che una app apre e un'altra no. Un file malformato non deve mai fermare la consegna né mettere a rischio il resto della cartella.
- Non è a suo agio con strumenti da fotografo: se deve imparare un catalogo, torna al Finder.

**Comportamenti e strumenti:**
Finder, Anteprima, Canva, cartelle condivise e sincronizzate. Usa il mouse più della tastiera, ma impara volentieri due o tre scorciatoie se le vede ripagate subito.

**Motivazioni:** Consegnare in tempo, senza errori evidenti, senza diventare un'esperta di software fotografico.
**Competenza tecnica:** Media. Sa cos'è un JPEG e cosa non è; di EXIF conosce la data e poco altro.

#### Percorso Utente - Adalgisa

| Fase | Azione | Pensiero | Emozione | Opportunità |
|---|---|---|---|---|
| Consapevolezza | Un collega le mostra l'app durante una consegna in ritardo | "Se mi dice davvero quale foto ha gli occhi aperti, mi cambia la giornata" | Speranza | Dimostrare il valore su un gruppo di raffica, che è il caso in cui il dolore è massimo |
| Considerazione | Teme che sia "uno strumento da fotografi" | "Non ho tempo di imparare Lightroom" | Timore di complessità | Nessuna importazione, nessuna configurazione: apri la cartella e sei operativa |
| Primo utilizzo | Seleziona 10 scatti simili e chiede "tieni le 3 migliori" | "Perché proprio queste tre?" | Sospetto | Mostrare motivazioni misurabili e realmente distinte tra loro; nessuna cancellazione automatica |
| Uso regolare | Triage con rating, gruppi di simili, rinomina massiva su pattern aziendale, smistamento in sottocartelle per canale | "Ho un flusso, e lo ripeto identico ogni settimana" | Sollievo, competenza | Salvare i pattern e le regole ricorrenti come preset riutilizzabili (crescita) |
| Advocacy | Rimanda la cartella al fotografo e lui vede le stelle nel suo software | "Le consegne le facciamo così, e non devo più scrivere elenchi" | Orgoglio professionale | I giudizi in sidecar standard rendono la cartella autosufficiente, a patto che l'interoperabilità sia provata su strumenti reali e non assunta |

---

## Brainstorming Insights

<!-- archetipo:prd section=brainstorming_insights required=true -->

> Scoperte chiave e direzioni alternative esplorate durante la sessione di inception e durante le tre revisioni architetturali successive.

### Assunti Messi in Discussione

- **"Le cinque frustrazioni sono cinque funzioni da aggiungere."** Falso: sono un unico problema. Il cuore dell'app non è la griglia di anteprime, ma il **ciclo di triage** guarda → giudica → agisci → prossima, interamente a tastiera. Ogni funzione va valutata su quanto accorcia quel ciclo.
- **"Esiste un 'migliore' oggettivo che un modello può calcolare."** In gran parte falso, e il prodotto ne dipende. Da qui la regola non negoziabile: **l'AI argomenta, non decreta**, e non cancella mai nulla da sola.
- **"L'AI è la funzione che vende, quindi va messa al centro."** Vera solo a metà: il differenziatore commerciale è l'AI, quello d'uso quotidiano è la **latenza**. Conseguenza: analisi **solo su richiesta, solo su una selezione**.
- **"Le frecce sono un dettaglio di comodità."** Falso: sono l'intero contratto di interazione, e vincolano la mappa dei tasti a essere completa dal primo giorno.
- **"Bisogna scegliere un solo criterio di selezione."** I criteri sono in **cascata ordinata**: raggruppamento, soggetto, qualità tecnica, estetica.
- **"L'indice locale è una cache buttabile."** Vero solo per ciò che è ricalcolabile. I giudizi sono creati dall'utente e hanno un contratto di durabilità proprio (ADR-003, ADR-013).
- **"Basta separare i giudizi dalla cache."** Insufficiente: nello stesso archivio erano finiti anche il **registro delle operazioni** e le **scritture non riuscite**, che non sono ricalcolabili. Con un pulsante "svuota indice" in interfaccia, quel pulsante distruggeva la cronologia di annullamento. Conseguenza: separazione **fisica**.
- **"Separare fisicamente i due archivi rende durevole quello durevole."** Falso, ed è l'errore simmetrico del precedente. La separazione protegge da **un solo** modo di perdere lo stato — il comando di svuotamento — e lascia aperti gli altri: corruzione dell'archivio, migrazione fallita, disco pieno, cancellazione accidentale, crescita illimitata della cronologia. La durabilità non è una proprietà della collocazione, è un **contratto operativo**: modalità di journaling e livello di sincronizzazione dichiarati, controllo di integrità all'avvio, percorso di recupero da corruzione, retention limitata, backup coerente.
- **"I due archivi non condividono invarianti."** Falso, ed era una comodità retorica scritta per rendere pulita la giustificazione della separazione: rating e stato di sincronizzazione vivono in entrambi. L'invariante esiste, ma è **direzionale** — stato durevole e sidecar sono **autorevoli**, la cache derivata può restare indietro ed essere riallineata. È questa direzionalità, non l'assenza di invarianti, a rendere accettabile che nessuna transazione attraversi i due archivi.
- **"Immagine e sidecar sono un'unità indivisibile."** Falso: **non esiste** una transazione che sposti due file — tantomeno ottocento — come un solo commit. Il registro non rende atomico un lotto, lo rende **recuperabile**.
- **"Un lotto interrotto viene ripreso o compensato."** Binario, e la realtà non lo è: volume smontato, file modificato dall'esterno, spazio esaurito, permesso revocato, Cestino svuotato. Servono almeno cinque esiti — completato, compensato, parzialmente recuperato, bloccato in attesa dell'utente, abbandonato dall'utente — e il contratto si riscrive: *sappiamo sempre riconoscere lo stato raggiunto, tentiamo la ripresa o la compensazione, e dichiariamo esplicitamente ciò che richiede intervento umano*.
- **"Un errore su un singolo file non interrompe mai il lotto."** Giusto per un errore **locale**, disastroso per uno **sistemico**. Se il volume è sparito o i permessi sono stati revocati, proseguire produce centinaia di fallimenti identici e lascia il lotto a metà nel modo peggiore. La distinzione appartiene al requisito, non all'implementazione.
- **"L'anteprima obbligatoria protegge l'utente."** Vera solo se le precondizioni vengono **ricontrollate dopo il dry-run**: tra anteprima e conferma il filesystem può cambiare.
- **"Il Cestino garantisce il ripristino."** Falso: il sistema sposta l'elemento e riferisce dove è finito, senza promettere che vi resti. È reversibile *per l'utente*, non garantito *dal sistema*.
- **"I giudizi sopravvivono agli spostamenti fatti fuori dall'app."** Non mantenibile: se l'utente sposta la sola immagine, il sidecar resta indietro e l'app non osserva la destinazione. Al posto della promessa, una **matrice esplicita dei casi**.
- **"L'hash è già calcolato, quindi l'identità di riserva è gratuita."** Contraddizione interna: i duplicati calcolano l'hash completo **solo su collisione**. E due duplicati esatti condividono l'hash. Resta **recupero best-effort**, mai identità.
- **"`volume + inode` è l'identità del file."** Formulazione artigianale al posto delle primitive di sistema, che hanno proprietà di persistenza diverse e note. Quale combinazione regga è un cancello, non una decisione da PRD.
- **"La riconciliazione con finestra di quiete risolve gli eventi del filesystem."** Risolve il caso facile: restavano fuori volumi, identificatori riavvolti, cambio della radice, cartelle sincronizzate, e il fatto che **una raffica continua non raggiunge mai la finestra**.
- **"Un tempo massimo di riconciliazione garantisce l'aggiornamento della vista."** Falso: su un volume di rete bloccato, un disco smontato o un servizio di sincronizzazione non disponibile nessun limite può garantire che l'operazione *termini*. Si può garantire che **venga avviata** entro il tempo massimo, che l'I/O sia annullabile e con scadenza, e che l'interfaccia mostri lo stato reale. Conseguenza: gli stati di freschezza della vista diventano requisiti visibili, non note tecniche.
- **"Rileggo il sidecar e riscrivo invariato ciò che non conosco."** Non protegge da un'altra applicazione che scrive tra la nostra lettura e la nostra sostituzione.
- **"Il coordinamento di sistema protegge la scrittura del sidecar."** Vero solo verso le applicazioni che **partecipano** al protocollo: è un meccanismo cooperativo, non impositivo. Uno strumento che scrive senza coordinarsi entra comunque nella finestra tra il controllo della versione e la sostituzione. Conseguenza: controllo della versione **dentro** l'accesso coordinato, verifica **dopo** la sostituzione, conservazione temporanea della versione precedente, recupero esplicito quando una scrittura non coordinata viene rilevata.
- **Il motivo ricorrente.** Filesystem, sidecar e coordinamento tra processi: tre volte lo stesso difetto di scrittura — **un meccanismo cooperativo o best-effort descritto come se fosse impositivo**. Non è stato un incidente isolato ma una tendenza, ed è diventata una regola dichiarata nel differenziatore: dove il sistema può soltanto tentare, il documento dice che tenta e dice cosa fa quando fallisce.
- **"Costi misurati, non stimati."** Letteralmente impossibile: per ammettere un lavoro **prima** di eseguirlo bisogna stimarne il costo. La formulazione corretta è *stime conservative calibrate su misure reali*, segmentate per tipo di lavoro, formato, classe di risoluzione e hardware, con margine di sicurezza e retroazione dalla pressione di memoria. E una media, per quanto misurata, non protegge dall'immagine anomala che consuma cinque volte il normale: serve misura a posteriori che ricalibra, e un limite per singolo elemento.
- **"Uno scheduler unico protegge le risorse."** Un punto unico di ammissione diventa un componente onnisciente e un collo di bottiglia; e le dimensioni in pixel non dicono nulla sul costo di un modello, di una texture o di un contenitore multipagina.
- **"Cancellare subito il lavoro delle celle uscite dallo schermo è una virtù."** Su uno scorrimento reale ributta via il lavoro appena fatto: serve una **banda di ritenzione con isteresi**, la cui ampiezza è un parametro del budget.
- **"La sandbox è la condizione per distribuire a terzi."** Falso, ed è un errore propagato attraverso tre versioni senza essere verificato: un `.dmg` notarizzato **è già** distribuzione a terzi. La sandbox è la condizione del **Mac App Store**. La conseguenza pratica è opposta a quella scritta finora: la distribuzione a terzi è disponibile dall'MVP e la sua esperienza di installazione va curata, invece di essere rinviata.
- **"Il perimetro di sicurezza dell'app è l'accesso al filesystem."** Falso, ed è l'unica lacuna di questo giro che il documento non aveva mai toccato. Il livello unico di accesso è un buon confine **di codice**, non **di sicurezza**: l'app è monoprocesso, non in sandbox, ha accesso ai file dell'utente, e **interpreta dati non fidati** — le immagini. Un difetto in un decodificatore gira con tutti i privilegi dell'app. E non è ipotetico: Adalgisa riceve ogni settimana cartelle prodotte da persone e apparecchi che non controlla. Il documento aveva un requisito che dice "nessuna immagine lascia il dispositivo" e nessuno che dicesse cosa succede quando un'immagine malformata **entra**.
- **"Il costo dell'MVP allargato è dichiarato, quindi gestito."** Non segue: dichiarare il costo affronta il rischio di **sforzo**, non quello di **integrazione**. Conseguenza: quattro cancelli tecnici e consegna a tappe (ADR-015).

### Nuove Direzioni Scoperte

- **Anti-problem ("come rendiamo questa app inutilizzabile?").** Ha prodotto i vincoli non funzionali più utili del documento. Le tre revisioni ne hanno aggiunti altrettanti: bruciare CPU reagendo a ogni evento; crescere in memoria fino all'arresto silenzioso; **promettere garanzie che il sistema non può mantenere**; buttare via il lavoro appena fatto a ogni movimento di scorrimento; e **proseguire ostinatamente un lotto quando il terreno sotto è sparito**.
- **"E se togliessimo l'AI?" (what if).** L'app resterebbe utile: quattro frustrazioni su cinque sono risolte senza. Questo ha dato l'ordine di implementazione ed è diventato la struttura delle tappe di consegna.
- **Audience flip (dal proprietario del Mac al team).** Preset condivisibili e distribuzione a terzi. Il secondo si è rivelato **già disponibile** una volta corretto l'equivoco sulla sandbox: non è una funzione di crescita, è una cura dell'esperienza da fare subito.
- **Il sidecar non è una difesa, è un'interfaccia.** È la prima funzione che fa parlare iMAGE Surfer la lingua degli altri strumenti — e proprio per questo la sua correttezza non si dimostra leggendo una specifica ma con un round-trip su strumenti reali, **incluso uno che non si coordina**.
- **La matrice dei casi come funzione di prodotto.** L'elenco esplicito di cosa l'app sa seguire e cosa no si è rivelato più utile della promessa che sostituisce: una garanzia falsa perde l'utente una volta sola, un limite dichiarato lo mette in condizione di lavorarci intorno.
- **Gli stati di freschezza della vista come funzione.** Nati per non promettere una riconciliazione che su un volume bloccato non può terminare, sono in realtà informazione che l'utente vuole comunque: *sto guardando dati aggiornati, o no?* È onestà che arriva in interfaccia invece di restare nel documento.
- **L'invariante direzionale come schema riusabile.** "Una sede è autorevole, le altre possono restare indietro ed essere riallineate" risolve il rapporto tra sidecar, stato durevole e cache senza chiedere transazioni distribuite a un filesystem che non le offre. Lo stesso schema regge la futura sincronizzazione tra più Mac.
- **Un cancello che può dire "non supportato".** Il cancello sugli eventi del filesystem deve poter concludere che **classi di volume diverse richiedono meccanismi diversi** — notifiche, riconciliazione periodica, aggiornamento manuale — fino a dichiarare supporto limitato su alcune. Un cancello che può solo confermare non è un cancello.
- **Il registro come funzione, non come dettaglio tecnico.** Rende possibile un annullamento che sopravvive alla chiusura, ed è la base della ripresa dopo un arresto: due scopi, un solo meccanismo, ed è la ragione per cui vive nello stato durevole.
- **Il versionamento semantico dei punteggi.** Senza, il primo aggiornamento di sistema rende i punteggi in cache silenziosamente incomparabili: la cache non è più veloce, è sbagliata.
- **I cancelli tecnici come parte del prodotto.** Quattro verifiche che possono invalidare una decisione architetturale non sono attività di piano: sono la differenza tra un'architettura proposta e una verificata.
- **La fine delle revisioni sulla carta.** Tre giri hanno prodotto miglioramenti reali e decrescenti. Le domande rimaste — quali primitive di identità reggono, quanto costa davvero un lavoro in memoria, se il sidecar interopera, se il recupero funziona da ogni punto di interruzione — non si chiudono leggendo il documento un'altra volta. Si chiudono misurando.

### Assunti da Validare

- **Identità del file.** Quale combinazione tra identificatore di risorsa, identificatore di documento, UUID del volume e bookmark regga sui casi reali è **la domanda aperta più importante del documento**, perché da essa dipende la matrice dei casi supportati. Cancello n°2.
- **Meccanismo di osservazione per classe di volume.** Se le notifiche del filesystem offrano lo stesso contratto su disco interno, volume esterno, cartella sincronizzata e volume di rete, o se per alcune classi servano riconciliazione periodica, aggiornamento manuale o supporto dichiarato come limitato. Cancello n°2, con mandato esplicito di poter concludere "non supportato".
- **Convenzione di nome del sidecar.** `foto.xmp` o `foto.jpg.xmp`? La prima è più diffusa, la seconda risolve la collisione tra `foto.jpg` e `foto.heic`. *Da decidere sul round-trip reale.*
- **Rappresentazione di "da scartare".** Candidato: la convenzione `xmp:Rating = -1`, più uniforme di `xmp:Label`. *Da verificare su strumenti reali.*
- **Comportamento con uno scrittore non coordinato.** Quanto è ampia in pratica la finestra tra controllo della versione e sostituzione, e se la verifica successiva alla scrittura basta a rilevare l'interferenza. *Cancello n°3, che deve includere deliberatamente uno strumento che ignora il coordinamento.*
- **Politica di conflitto in interfaccia.** Lo stato esplicito sostituisce la regola sulla data di modifica, ma resta da decidere **cosa mostra l'app**: risoluzione proposta con conferma, oppure due valori affiancati. *Da validare sull'uso reale.*
- **Retention della cronologia delle operazioni.** Per quanto tempo o per quanti lotti conservare il registro prima di potarlo, sapendo che potarlo significa rinunciare ad annullare lotti vecchi. *Compromesso tra reversibilità e crescita illimitata dell'archivio.*
- **Soglie del budget di memoria e calibrazione delle stime.** Le stime iniziali per tipo di lavoro, formato e classe di risoluzione sono ipotesi da misurare su hardware reale, dal Mac con meno memoria in target in su, e da correggere con la misura a posteriori. Cancello n°1.
- **Ampiezza della banda di ritenzione.** Compromesso diretto tra thrashing e memoria, da calibrare **insieme** al budget e non separatamente.
- **Finestra di quiete e tempo massimo di avvio della riconciliazione.** Due parametri distinti, entrambi da calibrare su scarichi di schede reali.
- **Euristica occhi aperti/chiusi.** Da calibrare su occhiali, profilo, occlusioni e volti piccoli, dichiarandone l'affidabilità. *Se non raggiunge un livello accettabile, va mostrata come indizio e non come criterio.*
- **Sovrapposizione tra qualità del volto e qualità tecnica.** Da misurare su materiale reale. *Il risultato decide se quel punteggio resta un criterio o diventa solo un filtro di ammissione allo stadio successivo.*
- **Utilità reale del punteggio estetico.** *Se dopo l'uso reale non sposta le decisioni, va declassato a criterio opzionale disattivabile.*
- **Peso e provenienza del modello estetico.** *Bundle unico più grande, oppure download al primo utilizzo?*
- **Superficie di attacco della decodifica.** Quanto sia realistico un file malformato capace di sfruttare un difetto nei decodificatori di sistema, e quale sia il costo effettivo di isolare decodifica e analisi in un processo separato. *Assunto per l'MVP: rischio accettato e dichiarato (ADR-016). Da rivedere se emergono episodi reali o se il costo dell'isolamento risulta basso.*
- **RAW rinviato alla crescita.** *Se in pratica gli scatti importanti sono RAW, la priorità va rivista subito.*
- **Ricorsività delle operazioni massive.** Assunto per l'MVP: solo cartella corrente. *La ricorsione moltiplica i modi in cui un'operazione può fare danni.*
- **Nessuna integrazione con la libreria Foto di macOS.** *Da confermare.*
- **Numero di "migliori" da tenere.** Parametro (default 3), non costante.
- **Tenuta dello scope.** Tre revisioni indipendenti hanno segnalato che l'insieme è più vicino a una v1 professionale che a un MVP. La risposta scelta è la consegna a tappe con cancelli, senza rimuovere funzioni. *Da rivedere alla fine del cancello n°1: Area 12 — Editing di base e il punteggio estetico sono i due candidati dichiarati al rinvio.*

### Rischi Principali

- **Rischio di esecuzione — latenza percepita.** È il rischio primario: se aprire una cartella da 3.000 immagini non è immediato, l'app perde contro il Finder a prescindere dal resto. Mitigazione: anteprime dal servizio di sistema con cache su disco, decodifica solo di ciò che serve, banda di ritenzione con isteresi, cache persistente. Verificato dal cancello n°1.
- **Rischio di adozione — sfiducia nell'AI.** Mitigazione: motivazioni sempre visibili **e realmente distinte**, sovrapposizioni dichiarate, soglie regolabili, nessuna azione distruttiva automatica.
- **Rischio di perdita dati sulle operazioni massive.** Mitigazione a cinque livelli: anteprima obbligatoria, ricontrollo delle precondizioni prima di agire, registro con passi idempotenti, **sospensione su errore sistemico**, eliminazioni sempre nel Cestino. Verificato dal cancello n°4.
- **Rischio di perdita del lavoro di giudizio.** Mitigazione: sidecar accanto all'immagine, stato durevole separato **e con contratto di durabilità proprio**, matrice dei casi dichiarata al posto di una promessa generale.
- **Rischio — lo stato durevole come unico punto di perdita.** Distinto dal precedente: una volta che registro, lotti aperti e scritture non riuscite vivono in un solo archivio, quell'archivio diventa critico. Separarlo dalla cache lo protegge dal comando di svuotamento e da nient'altro. Mitigazione: contratto operativo esplicito — journaling e sincronizzazione dichiarati, controllo di integrità all'avvio, percorso di recupero da corruzione che ricostruisce ciò che è ricostruibile e mette in quarantena il resto dichiarandolo, retention limitata, comportamento definito su disco pieno e migrazione fallita.
- **Rischio di fiducia — promettere garanzie non mantenibili.** Un limite dichiarato in anticipo si aggira; una garanzia smentita una volta sola distrugge la credibilità di tutte le altre. Mitigazione: le parole "sempre", "garantito" e "indivisibile" non compaiono dove il sistema può offrire soltanto recupero o best-effort, e ogni meccanismo cooperativo è descritto come tale.
- **Rischio tecnico — coerenza tra le sedi del dato.** Tre sedi dello stesso giudizio (sidecar, stato durevole, cache) sono tre modi di divergere. Mitigazione: **invariante direzionale** con ordine di scrittura dichiarato e riconciliazione delle righe non allineate all'avvio, invece di transazioni che il filesystem non offre.
- **Rischio tecnico — tempesta di eventi del filesystem.** Mitigazione: finestra di quiete **e** avvio garantito entro un tempo massimo, coalescenza per ambito, esclusione delle scritture proprie, gestione di identificatori persi o riavvolti e di volumi smontati, I/O annullabile. Verificato dal cancello n°2.
- **Rischio tecnico — esaurimento silenzioso della memoria.** Mitigazione: decodifica sempre ridimensionata, blocchi di rilascio per singolo elemento, code separate sotto stime conservative calibrate con limite per elemento, reazione alla pressione di memoria, test di lunga durata che fallisce la build. Verificato dal cancello n°1.
- **Rischio di interoperabilità — sidecar che gli altri strumenti non leggono.** Se Bridge o Lightroom non vedono le stelle, non è una funzione degradata ma assente. Verificato dal cancello n°3, che include uno scrittore non coordinato.
- **Rischio di sicurezza — dati non fidati in un processo con pieni privilegi.** L'app non è in sandbox, ha accesso ai file dell'utente e interpreta immagini che non ha prodotto: per Adalgisa il materiale esterno è il flusso di lavoro settimanale, non un caso limite. Un difetto in un decodificatore di sistema girerebbe con tutti i privilegi dell'app. Mitigazione per l'MVP: rischio dichiarato e accettato (ADR-016), difese disponibili senza costo attivate subito, nessun percorso che interpreti il contenuto di un file come codice, errori di decodifica contenuti e segnalati; isolamento di decodifica e analisi in un processo separato previsto come evoluzione, con l'innesto già collocato nell'architettura.
- **Rischio di adozione — attrito dei permessi al primo avvio.** Mitigazione: nessun permesso prima del gesto che lo motiva, nessun Accesso completo al disco come prerequisito, stato di rifiuto spiegato e recuperabile.
- **Rischio di integrazione — troppi sottosistemi che si incontrano lo stesso giorno.** Rilevato da tutte e tre le revisioni. Non si risolve accettando più tempo. Mitigazione: quattro cancelli prima del full build e consegna a tappe, ognuna utilizzabile da sola.
- **Rischio di scope — l'editing.** L'MVP contiene solo trasformazioni geometriche. Primo candidato dichiarato al rinvio se il cancello n°1 mostra che le stime non reggono.
- **Rischio operativo — assenza di sandbox.** Non limita la distribuzione diretta, che è disponibile dall'MVP tramite `.dmg` notarizzato; limita l'accesso al **Mac App Store** ed è il presupposto dell'isolamento del filesystem. Accettato per l'MVP; ogni accesso passa da un livello unico, che è il punto d'innesto dei bookmark con ambito di sicurezza.

---

## Product Scope

<!-- archetipo:prd section=product_scope required=true -->

### MVP - Minimum Viable Product

Il criterio di taglio dell'MVP: **risolvere tutte e cinque le frustrazioni dichiarate, più le tre capacità richieste (a, b, c), sulla scala reale di 10.000-50.000 immagini, senza mai mettere a rischio i file né il lavoro di giudizio dell'utente, e senza promettere garanzie che il sistema non può mantenere**. Tutto ciò che non serve a questo è fuori.

Lo scope è ampio e questo è riconosciuto: tre revisioni architetturali indipendenti hanno osservato che l'insieme è più vicino a una prima versione professionale che a un minimo prodotto. La risposta non è ridurre le funzioni ma **verificarne i presupposti prima di costruirle e consegnarle in tappe utilizzabili**, come descritto in *Percorso di consegna*.

**1. Apertura e navigazione delle cartelle**
- Apertura tramite trascinamento, dialogo di sistema, cartelle recenti o preferiti nella barra laterale.
- **Solo le immagini sono visibili** (frustrazione 1); contatore del contenuto non-immagine, che distingue i file collegati dal resto.
- Ordinamento per nome, data di scatto, data di modifica, dimensione, rating.
- Nessun permesso richiesto prima del gesto che lo motiva.

**2. Sincronizzazione con il filesystem e onestà sulla freschezza**
- Aggiornamento automatico quando la cartella cambia sotto l'app, anche per opera di altre applicazioni.
- Gli eventi del sistema sono un suggerimento: la verità è una riconciliazione per differenza.
- La riconciliazione è **avviata** entro un tempo massimo anche sotto raffica continua; il suo I/O è annullabile e con scadenza, perché su un volume bloccato nessuno può garantirne il completamento.
- **Lo stato di freschezza della vista è visibile**: aggiornata, aggiornamento in corso, potenzialmente obsoleta, volume non disponibile.
- Le modifiche avvenute mentre l'app era chiusa sono rilevate alla riapertura; volumi smontati, rimontati o con cronologia degli eventi non più disponibile sono gestiti esplicitamente.
- Su volumi di rete e cartelle sincronizzate i file non materializzati sono mostrati come tali e mai scaricati implicitamente; classi di volume diverse possono avere meccanismi diversi, dichiarati.

**3. Visualizzazione a griglia e anteprima grande**
- Griglia con cella regolabile fino a molto grande (frustrazione 2), fluida su migliaia di elementi.
- Anteprima grande a pannello e a schermo intero, con zoom fino a 1:1 e panoramica.
- **Navigazione integralmente a frecce** (frustrazione 3); selezione multipla da tastiera.

**4. Metadati sempre a portata d'occhio**
- Pannello permanente e commutabile con un tasto: dati file, dimensioni, EXIF, IPTC, GPS, spazio colore (frustrazione 4).
- Segue la selezione senza latenza percepibile; per selezioni multiple mostra i valori comuni.

**5. Giudizio, marcatura e loro durabilità**
- Rating 1-5 stelle e marcatura "da scartare" da tastiera; filtri per rating, marcatura, formato, intervallo di date.
- **I giudizi sono scritti in un sidecar XMP accanto all'immagine**, in formato standard. L'immagine originale non viene mai aperta in scrittura.
- **Ordine di autorità dichiarato**: stato durevole e sidecar sono autorevoli, la cache può restare indietro ed essere riallineata.
- **Stato di sincronizzazione esplicito** per ogni immagine, con conflitti mai risolti in silenzio, anche quando l'altra applicazione non si è coordinata.
- **Matrice dichiarata** dei casi in cui l'associazione regge, viene recuperata a tentativo, o non è recuperabile.

**6. Operazioni su file, singole e massive**
- Spostamento, copia, rinomina di singole immagini e di selezioni; il sidecar è incluso nel piano.
- Eliminazione **sempre tramite il Cestino di macOS**.
- **Rinomina massiva guidata da pattern** (capacità a) e **smistamento in sottocartelle per regole** (capacità b), con anteprima obbligatoria e ricontrollo delle precondizioni prima di agire.
- Ogni lotto ha un **esito dichiarato e visibile** tra cinque possibili — completato, compensato, parzialmente recuperato, bloccato in attesa dell'utente, abbandonato — e un errore **sistemico** sospende il lotto invece di moltiplicarsi.

**7. Duplicati**
- Rilevamento dei **duplicati esatti** per contenuto, con pannello di risoluzione che propone quale copia tenere.
- Rilevamento dei **gruppi di quasi-duplicati** con soglia regolabile.

**8. Selezione assistita — "tieni le migliori N"** (capacità c, frustrazione 5)
Pipeline in cascata: raggruppamento per similarità visiva e temporale → analisi del soggetto → qualità tecnica misurabile → punteggio estetico come spareggio finale.
- Proposta di N immagini (default 3, regolabile) **con le motivazioni sempre visibili** e le sovrapposizioni tra criteri dichiarate.
- Nessuna azione distruttiva automatica; esecuzione **solo su richiesta e solo su una selezione**.
- Ogni punteggio memorizzato porta con sé la versione degli strumenti e delle soglie che lo hanno prodotto.

**9. Editing di base**
- Rotazione di 90°, capovolgimento orizzontale e verticale, ritaglio con proporzioni libere e predefinite.
- Salvataggio come copia oppure sovrascrittura, con scelta esplicita e conservazione dei metadati.

**10. Fondamenta trasversali**
- **Due archivi locali distinti**: una cache eliminabile di dati ricalcolabili, e uno stato durevole con **contratto operativo proprio** — controllo di integrità, recupero da corruzione, retention limitata, comportamento definito su disco pieno.
- Un unico livello di accesso al filesystem: l'unico punto del codice che può scrivere, spostare o eliminare. È un confine **di codice**, non di sicurezza.
- **Code separate** per ingresso/uscita, decodifica, visione artificiale e archivio, sotto stime conservative calibrate su misure reali, con banda di ritenzione attorno alla parte visibile.
- Trattamento dei file come **dati non fidati**: nessun percorso interpreta il contenuto di un file come codice, gli errori di decodifica sono contenuti e segnalati, il rischio residuo è dichiarato.
- Mappa dei tasti completa e visibile in un pannello di aiuto.
- Accessibilità: etichette VoiceOver, rispetto di *Riduci movimento* e *Aumenta contrasto*, operabilità totale da tastiera.

### Percorso di consegna

Lo scope non è ridotto, ma non viene nemmeno costruito e integrato tutto insieme. La sequenza è vincolante.

**Tappa 0 — Cancelli tecnici.** Quattro verifiche che precedono il full build. Ognuna può invalidare una decisione architetturale, e ognuna produce un esito scritto che aggiorna gli ADR corrispondenti. **Un cancello può concludere che qualcosa non è supportabile**: è un esito legittimo, non un fallimento.

| # | Cancello | Domanda a cui risponde | ADR che può invalidare |
|---|---|---|---|
| 1 | **Prestazioni e memoria su 50.000 file** su dataset e hardware dichiarati | Il vincolo di latenza regge? Quali sono le stime di costo per tipo di lavoro, formato e classe di risoluzione, e con quale margine? Quanto deve essere ampia la banda di ritenzione? | ADR-009, e con esso NFR-P1, NFR-P9, NFR-P10 |
| 2 | **Eventi e identità** su APFS, volume esterno, cartella sincronizzata e volume di rete | Quali primitive di identità reggono? Come si comportano gli eventi quando un volume viene smontato o la cronologia non è più disponibile? **Quali classi di volume richiedono un meccanismo diverso, fino al supporto dichiarato come limitato?** | ADR-011, ADR-012, e la matrice dei casi di FR-054 |
| 3 | **Round-trip XMP** con Bridge, Lightroom, darktable e digiKam, **incluso uno scrittore che ignora il coordinamento** | Il sidecar è davvero interoperabile? Quale convenzione di nome? Come si rappresenta "da scartare"? La verifica successiva alla scrittura rileva l'interferenza non coordinata? | ADR-013 |
| 4 | **Crash injection** in ogni punto di un lotto, seguito da recupero | Da ogni punto di interruzione, quale dei cinque esiti si raggiunge? La compensazione è corretta? Quali casi finiscono legittimamente in "bloccato in attesa dell'utente"? | ADR-007 |

**Tappa 1 — Il triage a tastiera in piedi da solo.** Apertura cartella, filtro immagini, griglia, anteprima grande, navigazione a frecce, pannello metadati, permessi contestuali, stati di freschezza della vista. Risolve quattro frustrazioni su cinque ed è già utilizzabile.

**Tappa 2 — Giudizio e durabilità.** Rating e marcature, filtri, sidecar, stato di sincronizzazione, ordine di autorità, matrice dei casi, contratto di durabilità dello stato locale.

**Tappa 3 — Operazioni massive e duplicati.** Rinomina e smistamento con anteprima, ricontrollo delle precondizioni, registro e recupero a cinque esiti; duplicati esatti e quasi-duplicati.

**Tappa 4 — Selezione assistita ed editing.** Pipeline di analisi con motivazioni, punteggi versionati; trasformazioni geometriche. È l'ultima perché dipende da tutte le altre.

### Growth Features (Post-MVP)

- **Supporto RAW** (CR2/CR3, NEF, ARW, DNG, ORF) con gestione delle coppie RAW+JPEG e sidecar condiviso dalla coppia.
- **Isolamento di decodifica e analisi in un processo separato**, che riduce il danno di un difetto in un decodificatore da compromissione dell'app a caduta di un servizio (vedi ADR-016).
- **Editing non distruttivo**: regolazioni tonali con file affiancato e storico reversibile; l'originale non viene mai toccato.
- **Preset riutilizzabili e condivisibili** per pattern di rinomina e regole di smistamento.
- **Confronto affiancato** di 2-4 immagini con zoom sincronizzato.
- **Ricerca e filtri cross-cartella** sulla cache locale.
- **Parole chiave e tag**: keyword nel sidecar e, su richiesta esplicita e per lotti confermati, scrittura IPTC dentro i file.
- **Classificazione automatica per soggetto** usando la classificazione di sistema.
- **Esportazione** con ridimensionamento, conversione di formato e rimozione selettiva dei metadati sensibili.
- **Vista mappa** per le immagini geolocalizzate.
- **App Sandbox** con cartelle autorizzate dall'utente, presupposto del Mac App Store e dell'isolamento del filesystem.
- **Aggiornamenti automatici** sul canale di distribuzione diretta.
- **Operazioni ricorsive** sull'albero delle sottocartelle, con protezioni aggiuntive.

### Vision (Future)

- **Ricerca semantica in linguaggio naturale** sugli embedding già calcolati in locale, senza mai inviare nulla in rete.
- **Assistente di curation**: dall'insieme di un evento propone una selezione ragionata e una struttura di cartelle, spiegando ogni scelta.
- **Cartelle intelligenti** con regole persistenti che si applicano da sole al materiale nuovo.
- **Sincronizzazione dello stato tra più Mac**, con lo stesso schema di autorità direzionale usato tra sidecar, stato durevole e cache.
- **Supporto video** con lo stesso modello di triage, estratto sui fotogrammi chiave.
- **Estendibilità**: regole e criteri di punteggio definibili dall'utente.

---

## Technical Architecture

<!-- archetipo:prd section=technical_architecture required=true -->

> **Proposta da:** Leonardo (Architect)

### System Architecture

Applicazione **nativa macOS, monoprocesso, interamente locale**: nessun server, nessuna rete a tempo di esecuzione (unica eccezione possibile, il download iniziale del modello estetico se non incluso nel bundle), nessun account.

Il vincolo "solo macOS" è sfruttato deliberatamente: decodifica veloce di ogni formato fotografico, embedding di similarità visiva e analisi dei volti sono **già presenti nel sistema operativo**, accelerate su GPU e Neural Engine.

L'architettura riconosce **tre nature di dato**, con garanzie diverse, e le tiene in sedi diverse:

- **Dato derivato** — metadati letti dai file, hash, feature print, anteprime, punteggi. Ricalcolabile: vive in una cache che può essere distrutta senza perdita.
- **Dato autorale** — stelle e marcature. Non esiste altrove: viene scritto **accanto all'immagine** in un sidecar standard.
- **Stato durevole di processo** — registro delle operazioni, lotti incompleti, giudizi in attesa di scrittura o con scrittura fallita, stato di sincronizzazione. Non è ricalcolabile e non è ancora nel sidecar: sta in un archivio separato **con un contratto di durabilità proprio**, perché la sola separazione dal comando di svuotamento non lo protegge da corruzione, migrazione fallita, disco pieno o crescita illimitata.

Le tre sedi si tengono insieme con un **invariante direzionale**, non con transazioni che il filesystem non offre: **stato durevole e sidecar sono autorevoli, la cache derivata può restare indietro ed essere riallineata**. L'ordine è dichiarato: interfaccia ottimistica → scrittura nello stato durevole (prima scrittura durevole: finché non riesce, il giudizio non è accettato e l'interfaccia lo dice) → tentativo di scrittura del sidecar → aggiornamento opportunistico della cache → riconciliazione delle righe non allineate al riavvio.

Il contratto complessivo si esprime in tre parole scelte con cura, e nessuna di esse è *garantito*:

- **Ricostruibile** — la cache derivata, in ogni momento e integralmente.
- **Recuperabile** — un lotto di operazioni su file. Non atomico: non esiste una transazione multi-file, quindi ciò che si offre è riconoscere sempre lo stato raggiunto, tentare ripresa o compensazione, e **dichiarare esplicitamente ciò che richiede intervento umano**.
- **Best-effort** — il recupero dell'associazione tra giudizio e immagine dove il collegamento diretto è perso, e la protezione della scrittura del sidecar verso applicazioni che non si coordinano. Ogni caso è classificato, e i casi non supportati sono dichiarati tali.

```text
Cartella su disco  ◀── osservatore FS ──┐
   │  (enumerazione + filtro UTType)     │  eventi = suggerimento
   ▼                                     │  verità = riconciliazione per differenza
Catalogo in memoria                      │  quiete + AVVIO garantito entro tempo max
   │  identità: primitive di sistema      │  (il completamento non è garantibile:
   │  validità: mtime + size               │   I/O annullabile e con scadenza)
   │                                       │  ID legato al volume; ID persi o riavvolti,
   │                                       │  volume smontato, radice cambiata →
   │                                       │  riconciliazione completa
   │                                       │  meccanismo per classe di volume
   ├────────────┬──────────────────────────┘
   │            │                            ┌──────────────────────────────┐
   │            │                            │ Stato di freschezza visibile │
   │            │                            │ aggiornata / in corso /      │
   │            │                            │ obsoleta / volume assente    │
   │            │                            └──────────────────────────────┘
   │            ▼
   │      AUTORITÀ ──▶ Sidecar XMP accanto all'immagine
   │      (1) DurableState   coordinamento cooperativo: versione controllata
   │      (2) sidecar        DENTRO l'accesso coordinato, verifica DOPO la
   │      (3) cache          sostituzione, versione precedente conservata,
   │                         recupero se rilevata scrittura non coordinata
   │            │
   │            ▼
   │      ┌──────────────────┬──────────────────────────────┐
   │      │  DerivedCache    │  DurableState                │
   │      │  eliminabile     │  NON eliminabile             │
   │      │  può restare     │  + contratto operativo:      │
   │      │  indietro        │    integrità all'avvio,      │
   │      │  metadati, hash, │    recupero da corruzione,   │
   │      │  feature print,  │    retention limitata,       │
   │      │  punteggi        │    disco pieno definito      │
   │      └──────────────────┴──────────────────────────────┘
   │            ▲
   ▼            │
Code separate sotto budget comune
   I/O · decodifica · Vision/CoreML · archivio
   stime conservative CALIBRATE su misure reali, per tipo/formato/risoluzione
   + margine + misura a posteriori + limite per singolo elemento
   priorità al visibile, banda di ritenzione con isteresi
   │
   ▼
Griglia / Anteprima grande        ◀── dati non fidati: nessun percorso esegue
   │                                   contenuto, errori di decodifica contenuti
   │ (su richiesta, su una selezione)   (isolamento in processo separato: crescita)
   ▼
Pipeline di analisi  →  punteggi versionati (revisione Vision, modello, soglie)
   raggruppamento → soggetto → qualità tecnica → estetica
   │                  └── sovrapposizioni dichiarate, non nascoste
   ▼
Proposta con motivazioni  →  conferma utente
   │
   ▼
FileOps: macchina a stati con log di intenti
   piano + precondizioni → RICONTROLLO precondizioni → prepared
   → passi idempotenti registrati uno a uno
   → esito fra CINQUE: completato · compensato · parzialmente recuperato
                       · bloccato in attesa dell'utente · abbandonato
   │  errore locale = saltato · errore sistemico = lotto sospeso
   │  attraverso il livello unico di accesso (confine di codice, non di sicurezza)
   ▼
Cestino di macOS (reversibile per l'utente, non garantito dal sistema)
```

**Pattern Architetturale:** MVVM su SwiftUI con nucleo di dominio in pacchetti SPM indipendenti dalla UI; concorrenza strutturata con attori; code specializzate sotto una politica di budget comune; separazione fisica tra cache derivata e stato durevole, tenute insieme da un invariante direzionale di autorità; operazioni su file come macchina a stati recuperabile a cinque esiti; ogni scrittura sul filesystem attraversa un livello unico.

**Componenti Principali:**

- **`Catalog`** — enumerazione, filtro per `UTType`, **identità** e **validità** come chiavi distinte, ordinamenti e filtri. L'identità usa le primitive che il sistema espone (bookmark persistenti, identificatori di risorsa e di documento, UUID del volume) nella combinazione stabilita dal cancello n°2; l'hash del contenuto è **recupero best-effort**, non identità, e non viene calcolato in anticipo su tutta la cartella. Contiene l'**osservatore** e il **riconciliatore**: l'osservatore smorza e coalesce, il riconciliatore rienumera e calcola la differenza con I/O annullabile e soggetto a scadenza. Espone lo **stato di freschezza** della vista, perché su un volume bloccato il completamento non è garantibile e la vista deve dirlo.
- **`Metadata`** — lettura di EXIF/IPTC/GPS/TIFF via ImageIO; normalizzazione in un modello tipizzato, tollerante ai metadati assenti e ai file malformati.
- **`Sidecar`** — lettura e scrittura dei giudizi in `.xmp` affiancato. Scrittura **atomica sul singolo file** e **conservativa** sui campi sconosciuti, sotto coordinamento di sistema tra processi. Poiché quel coordinamento è **cooperativo e non impositivo**, la protezione è a più livelli: controllo della versione osservata **dentro** l'accesso coordinato, **verifica dopo la sostituzione**, conservazione temporanea della versione precedente, e **recupero esplicito** quando si rileva che un'applicazione non coordinata ha scritto nel frattempo. Non apre mai in scrittura il file immagine.
- **`Thumbnails`** — anteprime da QuickLook Thumbnailing con cache su disco a due misure; decodifica **sempre ridimensionata**, mai a piena risoluzione; cache in memoria con limite di costo e svuotamento sulla pressione di memoria.
- **`Work`** — politica di ammissione del lavoro asincrono. **Code specializzate** per ingresso/uscita, decodifica, visione artificiale e archivio, coordinate da un **budget di memoria comune**. Poiché ammettere un lavoro richiede di stimarne il costo prima di eseguirlo, le stime sono **conservative e calibrate su misure reali**, segmentate per tipo di lavoro, formato e classe di risoluzione, con margine di sicurezza; la misura a posteriori ricalibra, e un **limite per singolo elemento** interrompe l'elemento anomalo invece di lasciarlo trascinare giù il processo. Mantiene una **banda di ritenzione con isteresi** attorno alla parte visibile; avvolge ogni elemento in un blocco di rilascio esplicito.
- **`Duplicates`** — duplicati esatti a stadi di costo crescente; quasi-duplicati per distanza tra feature print combinata alla vicinanza temporale.
- **`Quality`** — analisi del soggetto e della qualità tecnica su immagine ridimensionata; punteggio estetico da modello Core ML come ultimo criterio. Lo stato aperto/chiuso degli occhi è un'**euristica costruita sui landmark**, dichiarata e calibrata. Il punteggio di qualità di cattura del volto è **olistico** e si sovrappone in parte ai criteri tecnici: la sovrapposizione è dichiarata. Ogni punteggio porta con sé **revisione della visione artificiale, versione del modello, preprocessing, algoritmo e soglie**.
- **`Access`** — livello unico di accesso al filesystem: l'unico punto autorizzato a creare, scrivere, spostare o eliminare. Custodisce i bookmark, la richiesta contestuale dei permessi e la diagnosi di un accesso negato. È un **confine di codice, non di sicurezza**: non riduce i privilegi del processo e non contiene un difetto di decodifica (ADR-016). È il punto d'innesto della futura sandbox.
- **`FileOps`** — **macchina a stati con log di intenti**: registra piano e precondizioni, **ricontrolla le precondizioni dopo il dry-run e prima di agire**, marca il lotto come preparato, esegue passi **idempotenti** registrando ognuno, e conclude in uno di **cinque esiti** — completato, compensato, parzialmente recuperato, bloccato in attesa dell'utente, abbandonato dall'utente. Distingue **errore locale** (il file viene saltato, il lotto prosegue) da **errore sistemico** (volume scomparso, permessi revocati, spazio esaurito: il lotto è sospeso). Il sidecar è incluso nel piano. Scrive esclusivamente attraverso `Access`.
- **`DerivedCache`** — archivio SQLite **eliminabile**: metadati, hash già calcolati, feature print, punteggi versionati, copia dei giudizi per filtrare e ordinare. **Non è autorevole**: può restare indietro rispetto a stato durevole e sidecar, ed è riallineata dalla riconciliazione delle righe non allineate.
- **`DurableState`** — archivio SQLite **separato, non eliminabile dall'interfaccia, e con contratto operativo dichiarato**: modalità di journaling e livello di sincronizzazione scelti per la durabilità e non per la velocità, controllo di integrità all'avvio, percorso di recupero da corruzione che ricostruisce ciò che è ricostruibile e mette in quarantena il resto dichiarandolo, **retention limitata della cronologia** con politica esplicita, comportamento definito su disco pieno e su migrazione fallita. È la sede autorevole insieme al sidecar, e ciò che un backup deve contenere.
- **`UI`** — SwiftUI per struttura, barra laterale, pannelli e dialoghi; ponte AppKit su `NSCollectionView` per la griglia. Mappa dei tasti centralizzata in un unico punto.

### Technology Stack

| Livello | Tecnologia | Versione | Motivazione |
|---|---|---|---|
| Linguaggio | Swift | 6.x (concorrenza stretta) | Unico linguaggio di prima classe per le API di sistema che costituiscono il valore dell'app; la concorrenza strutturata è il modello richiesto dalle pipeline con cancellazione |
| Piattaforma applicativa | AppKit + Swift Concurrency | macOS 15+ | Il target è una sola piattaforma; nessun livello di astrazione multipiattaforma da mantenere |
| Framework di interfaccia | SwiftUI, con ponte AppKit (`NSCollectionView`) per la griglia | macOS 15+ | SwiftUI per pannelli e dialoghi; `NSCollectionView` dove serve riuso di celle su decine di migliaia di elementi |
| Anteprime e decodifica | QuickLook Thumbnailing + ImageIO + Core Image | di sistema | Copertura nativa dei formati senza dipendenze; decodifica ridimensionata e trasformazioni accelerate |
| Identità dei file | Chiavi di risorsa di Foundation (identificatore di risorsa, di documento, di volume) + bookmark persistenti | di sistema | Primitive esposte dal sistema al posto di una formulazione artigianale; hanno proprietà di persistenza diverse tra loro, e la combinazione da adottare è l'esito del cancello n°2 |
| Osservazione del filesystem | File System Events con eventi a granularità di file, identificatore d'evento persistito e legato al volume | di sistema | Rilevare le modifiche senza interrogazione periodica e riprendere dopo la chiusura; gli eventi a granularità di file sono deliberatamente molto più numerosi. Il contratto può non essere uniforme fra classi di volume: il cancello n°2 può concludere che alcune richiedono riconciliazione periodica, aggiornamento manuale o supporto limitato |
| Coordinamento tra processi | `NSFileCoordinator` | di sistema | Coordina gli accessi con le applicazioni che **partecipano** al protocollo. È cooperativo, non impositivo: non impedisce a uno scrittore non coordinato di intervenire, quindi va accompagnato da verifica successiva alla scrittura e recupero esplicito |
| Visione artificiale | Vision (feature print, rilevamento volti, qualità di cattura, landmark) | di sistema | Embedding e analisi volti sul Neural Engine. Fornisce **landmark** oculari, non un classificatore aperto/chiuso: quella conclusione è nostra ed è dichiarata come euristica |
| Modello estetico | Modello open source di image-quality assessment convertito in Core ML | Core ML di sistema | Criterio di gradimento, eseguito **solo su gruppi già formati e solo su richiesta** |
| Giudizi portabili | Sidecar XMP (`xmp:Rating`, rappresentazione dello scarto) come XML affiancato | XMP Basic | Formato standard letto dai principali strumenti fotografici; nessuna dipendenza esterna e nessuna riscrittura del file immagine. L'interoperabilità è un **obiettivo verificato dal cancello n°3**, non una proprietà del formato |
| Archivi locali | SQLite, in **due file distinti** (cache derivata, stato durevole) con impostazioni di durabilità diverse | 3 (di sistema) | Cicli di vita e requisiti di durabilità diversi devono stare in archivi diversi; lo stato durevole privilegia la sicurezza della scrittura, la cache la velocità |
| Accesso ai dati | GRDB.swift | 7.x | Accesso SQLite tipizzato e testabile, con migrazioni versionate e osservazione delle modifiche |
| Isolamento di processo | XPC | di sistema | **Non usato nell'MVP.** Registrato come innesto previsto per isolare decodifica e analisi di dati non fidati (ADR-016), così che introdurlo non richieda di rivedere i confini dei componenti |
| Autenticazione | Nessuna | — | App locale monoutente, senza account e senza servizi remoti |
| Test | Swift Testing (unità e integrazione) + XCUITest (percorsi critici a tastiera) | di sistema | I moduli SPM sono testabili senza avviare l'interfaccia; XCUITest copre la navigazione a tastiera |
| Test di robustezza | Lunga durata su cartella di grandi dimensioni; **iniezione di arresti** in ogni punto di un lotto; **corpus di file malformati** | — | Crescita di memoria, recupero dopo un arresto e tolleranza ai dati non fidati non emergono in un test unitario |

### Project Structure

**Pattern organizzativo:** target applicativo Xcode sottile sopra pacchetti SPM locali per dominio; ogni pacchetto testabile in isolamento senza avviare la UI.

```text
iMAGE-Surfer/
├── iMAGESurfer.xcodeproj
├── App/                          # target applicativo: ciclo di vita, finestre, comandi, cablaggio
│   ├── iMAGESurferApp.swift
│   ├── Commands/                 # menu e mappa dei tasti centralizzata
│   ├── Onboarding/               # spiegazione contestuale dei permessi e stati di accesso negato
│   ├── Resources/                # icone, Assets, modello Core ML compilato
│   └── iMAGESurfer.entitlements
├── Packages/
│   ├── Catalog/                  # enumerazione, filtro tipi, identità/validità, osservatore + riconciliatore, freschezza
│   ├── Metadata/                 # ImageIO -> modello metadati tipizzato
│   ├── Sidecar/                  # XMP affiancato: coordinamento, verifica post-scrittura, conflitti, recupero
│   ├── Thumbnails/               # QuickLook + cache su disco + decodifica ridimensionata
│   ├── Work/                     # code specializzate, stime calibrate, limite per elemento, banda di ritenzione
│   ├── Duplicates/               # hash esatti a stadi + clustering quasi-duplicati
│   ├── Quality/                  # Vision, Core Image, Core ML: punteggi scomposti e versionati
│   ├── Access/                   # livello unico di accesso, bookmark, permessi (confine di codice)
│   ├── FileOps/                  # macchina a stati, log di intenti, passi idempotenti, cinque esiti
│   ├── DerivedCache/             # SQLite eliminabile, non autorevole
│   ├── DurableState/             # SQLite durevole: integrità, recupero, retention, sede autorevole
│   └── DesignSystem/             # componenti condivisi, tipografia, accessibilità
├── Spikes/                       # i quattro cancelli tecnici: codice, dataset, esiti scritti
│   ├── 01-scale-memory/
│   ├── 02-fsevents-identity/
│   ├── 03-xmp-roundtrip/         # include uno scrittore che ignora il coordinamento
│   └── 04-crash-recovery/
├── Tests/
│   ├── Fixtures/                 # raffiche, duplicati, EXIF mancanti, HEIC, orientamenti, sidecar di terzi
│   ├── Malformed/                # corpus di file troncati, corrotti e con intestazioni incoerenti
│   ├── Soak/                     # lunga durata: memoria e raffiche di eventi
│   └── CrashInjection/           # interruzione e recupero su lotti di operazioni
├── Scripts/
│   ├── build-dmg.sh              # pacchettizzazione e notarizzazione
│   └── lint.sh
├── docs/                         # PRD, wiki, mockup, esiti dei cancelli
└── .github/workflows/ci.yml
```

### Development Environment

Ambiente completamente locale, senza servizi da avviare: si apre il progetto Xcode e si esegue. Nessun contenitore, nessun database esterno, nessuna variabile d'ambiente obbligatoria.

**Permessi:** l'app **non richiede l'Accesso completo al disco** per funzionare. Al primo utilizzo di una cartella in Scrivania, Documenti, Download, su volume rimovibile o di rete, macOS mostra il proprio dialogo di consenso con la motivazione dichiarata nel bundle; le cartelle aperte dal pannello di sistema o trascinate sull'app sono accessibili senza ulteriori richieste. L'Accesso completo al disco resta un'opzione, mai un prerequisito. In sviluppo, compilazioni successive possono invalidare il consenso già concesso: è un fastidio noto della fase di sviluppo, non dell'app distribuita.

**Materiale di prova.** Le fixture (raffiche reali, duplicati byte-identici, immagini senza EXIF, HEIC, orientamenti EXIF non standard, sidecar XMP prodotti da strumenti di terze parti, **file troncati e corrotti**) sono versionate nel repository. I cancelli tecnici richiedono in aggiunta materiale non versionabile — un insieme di 50.000 file e volumi di prova esterni, sincronizzati e di rete — la cui procedura di generazione e configurazione è versionata sotto `Spikes/`, insieme all'esito scritto di ogni cancello.

**Strumenti richiesti:** macOS 15 o successivo su Apple Silicon; Xcode 16 o successivo (Swift 6); `swift-format` e SwiftLint per lo stile; `xcodebuild` per build e test da riga di comando; `notarytool` e `create-dmg` per la distribuzione; Python con `coremltools` **solo** in fase di conversione del modello estetico, mai a tempo di esecuzione.

### CI/CD & Deployment

**Strumento di build:** `xcodebuild` (SPM per la risoluzione delle dipendenze dei pacchetti locali e di GRDB).

**Pipeline:** GitHub Actions su runner macOS. Ad ogni push: `swift-format --lint` e SwiftLint → build dei pacchetti SPM → test unitari → build del target applicativo → XCUITest sui percorsi critici a tastiera → **test di iniezione di arresti** sui lotti, che verificano quale dei cinque esiti si raggiunge da ogni punto di interruzione → **test sul corpus di file malformati**, che verificano che nessun file corrotto interrompa il caricamento della cartella. Su ramo principale e prima di ogni rilascio, in aggiunta: **test di lunga durata** con soglie di fallimento dichiarate su occupazione di memoria di picco, crescita nel tempo, e numero di riconciliazioni prodotte da una raffica sintetica. Su tag di versione: build Release con hardened runtime, firma, notarizzazione, `.dmg` e pubblicazione come artefatto.

**Deployment:** distribuzione **diretta come `.dmg` notarizzato**, non in sandbox. È già un canale di distribuzione a terzi pienamente utilizzabile: l'assenza di sandbox esclude il Mac App Store, non la distribuzione. Nessun canale di aggiornamento automatico nell'MVP.

**Infrastruttura di destinazione:** il Mac dell'utente. Nessuna infrastruttura server, nessun servizio remoto, nessuna telemetria.

### Architecture Decision Records (ADR)

- **ADR-001 — App nativa Swift/SwiftUI, non Electron o multipiattaforma.** *Decisione:* nativa. *Motivo:* le capacità portanti sono servizi di sistema accelerati su hardware; in un runtime web andrebbero reimportate come dipendenze pesanti e girerebbero molto più lente, colpendo il rischio primario. *Conseguenza:* il codice non è portabile fuori da macOS — vincolo dichiarato del prodotto, non limite.
- **ADR-002 — Anteprime da QuickLook Thumbnailing, non decodifica propria.** *Decisione:* il servizio di sistema è la sorgente primaria, con ImageIO come riserva e per lo zoom 1:1. *Motivo:* copertura gratuita dei formati e riuso della cache di sistema. *Conseguenza:* si dipende da una qualità non controllata nel dettaglio; accettabile per la griglia, non per lo zoom, dove si decodifica direttamente — sempre a dimensione dichiarata.
- **ADR-003 — Tre nature di dato, due archivi fisici, un invariante direzionale.** *Decisione:* `DerivedCache` (SQLite eliminabile) contiene solo ciò che è ricalcolabile. `DurableState` (SQLite separato, senza pulsante di svuotamento) contiene registro, lotti incompleti, giudizi in attesa o falliti, stato di sincronizzazione e preferenze autorali, **con un contratto operativo di durabilità dichiarato**: journaling e livello di sincronizzazione scelti per la sicurezza della scrittura, controllo di integrità all'avvio, percorso di recupero da corruzione, retention limitata della cronologia, comportamento definito su disco pieno e migrazione fallita. Le sedi sono tenute insieme da un **invariante direzionale**: stato durevole e sidecar sono **autorevoli**, la cache può restare indietro ed essere riallineata, con ordine di scrittura dichiarato (stato durevole → sidecar → cache) e riconciliazione delle righe non allineate al riavvio. *Motivo:* due correzioni successive. La prima: la revisione 1.1 aveva lasciato registro e scritture fallite nella cache eliminabile, dove il comando di svuotamento li distruggeva. La seconda: separare i due archivi protegge da quel solo comando e da nient'altro — corruzione, migrazione fallita, disco pieno e crescita illimitata restavano scoperti, quindi la durabilità va scritta come contratto e non dedotta dalla collocazione. Infine, l'affermazione che i due archivi "non condividano invarianti" era falsa: rating e stato di sincronizzazione vivono in entrambi. L'invariante esiste ed è direzionale, ed è la direzionalità — non l'assenza di invarianti — a rendere accettabile che nessuna transazione li attraversi. *Conseguenza:* due file con impostazioni di durabilità diverse; il comando di svuotamento agisce solo sul primo; il secondo è ciò che un backup deve contenere; la cache non è mai fonte in caso di divergenza; e la retention della cronologia diventa un compromesso dichiarato tra reversibilità e crescita dell'archivio.
- **ADR-004 — Quasi-duplicati tramite feature print di Vision, non hash percettivo artigianale.** *Decisione:* distanza tra embedding di sistema, combinata alla vicinanza temporale EXIF. *Motivo:* qualità superiore su ritagli, esposizioni e piccoli movimenti, con costo sul Neural Engine. *Conseguenza:* la soglia non ha significato assoluto e va calibrata, regolabile con anteprima visiva immediata.
- **ADR-005 — Consenso progressivo ai permessi; la sandbox è la condizione del Mac App Store, non della distribuzione.** *Decisione:* `.dmg` notarizzato con hardened runtime, senza App Sandbox; nessuna richiesta di Accesso completo al disco, ma consenso per categoria chiesto contestualmente e accesso concesso dal pannello di apertura o dal trascinamento. Il FDA è un'opzione. *Motivo:* un'app fuori sandbox accede alle cartelle scelte dall'utente senza FDA, che serve solo per ciò che è protetto in modo speciale: chiederlo all'avvio era costo di adozione a beneficio nullo. Quanto alla sandbox, le versioni precedenti di questo ADR affermavano che la sua assenza mettesse "la distribuzione a terzi fuori portata": è falso, e l'errore è stato propagato attraverso tre versioni senza essere verificato. Un `.dmg` notarizzato **è** distribuzione a terzi; la sandbox è il presupposto del **Mac App Store** e dell'isolamento del filesystem. *Conseguenza:* la distribuzione diretta è disponibile fin dall'MVP e la sua esperienza di installazione va curata invece che rinviata; resta fuori portata il solo Mac App Store. Nessun permesso viene chiesto prima del gesto che lo motiva; un accesso negato produce uno stato spiegato e recuperabile; richieste, bookmark e diagnosi vivono in `Access`, punto d'innesto della futura sandbox.
- **ADR-006 — Il modello estetico gira solo su richiesta, e solo dentro un gruppo già formato.** *Decisione:* mai in scansione di cartella. *Motivo:* protegge il vincolo di latenza. *Conseguenza:* il punteggio estetico non è disponibile come criterio di ordinamento globale finché non esistono prove di prestazione che lo permettano.
- **ADR-007 — Operazioni massive recuperabili, non atomiche, con cinque esiti dichiarati.** *Decisione:* `FileOps` è una macchina a stati con log di intenti scritto **prima** dell'azione: piano e precondizioni registrati → **ricontrollo delle precondizioni dopo il dry-run e immediatamente prima di agire** → lotto preparato → passi **idempotenti** eseguiti e registrati uno a uno → conclusione in uno di **cinque esiti**: completato, compensato, parzialmente recuperato, bloccato in attesa dell'utente, abbandonato dall'utente. Un **errore locale** su un file lo fa saltare e il lotto prosegue; un **errore sistemico** — volume scomparso, permessi revocati, spazio esaurito — **sospende** il lotto. Le eliminazioni passano dal Cestino. *Motivo:* due correzioni. La prima: la promessa di un'unità indivisibile è insostenibile perché non esiste una transazione multi-file; il registro non rende atomico un lotto, lo rende recuperabile. La seconda: "ripreso o compensato" è binario, ma volume smontato, file modificato dall'esterno, spazio esaurito, permesso revocato o Cestino svuotato producono situazioni in cui **nessuna delle due** è possibile. Il contratto realistico non è "possiamo sempre concludere o riportare indietro" ma *"riconosciamo sempre lo stato raggiunto, tentiamo ripresa o compensazione, e dichiariamo esplicitamente ciò che richiede intervento umano"*. Analogamente, proseguire un lotto quando l'errore è sistemico produce centinaia di fallimenti identici e lo lascia a metà nel modo peggiore. *Conseguenza:* ogni passo va progettato idempotente e compensabile; gli esiti sono parte dell'interfaccia e non del registro interno, perché "bloccato in attesa dell'utente" richiede che l'utente lo sappia; la distinzione locale/sistemico va decisa per ogni classe di errore; il registro vive in `DurableState`. Anche il Cestino è dichiarato per quello che è: il sistema sposta l'elemento e riferisce dove è finito, senza promettere che vi resti. Verificato dal cancello n°4, che deve stabilire quali punti di interruzione finiscono legittimamente in "bloccato".
- **ADR-008 — `NSCollectionView` per la griglia, SwiftUI per tutto il resto.** *Decisione:* ponte AppKit limitato alla griglia. *Motivo:* riuso di celle e fluidità su decine di migliaia di elementi. *Conseguenza:* una superficie AppKit da mantenere, confinata a un solo componente con contratto esplicito.
- **ADR-009 — Code specializzate sotto stime conservative calibrate, con banda di ritenzione.** *Decisione:* il lavoro asincrono passa da **code separate** — ingresso/uscita, decodifica, visione artificiale e modelli, archivio — coordinate da una politica di **budget di memoria comune**. Poiché l'ammissione precede l'esecuzione, il costo va **stimato**: le stime sono **conservative e calibrate su misure reali**, segmentate per tipo di lavoro, formato, classe di risoluzione e hardware, con margine di sicurezza, **misura a posteriori che ricalibra** e un **limite per singolo elemento** che interrompe l'elemento anomalo. Attorno alla parte visibile si mantiene una **banda di ritenzione con isteresi**; ogni elemento è avvolto in un blocco di rilascio esplicito; la decodifica è sempre a dimensione dichiarata; il budget si riduce sotto pressione di memoria. *Motivo:* tre correzioni. Un punto unico di ammissione concentra in un componente la conoscenza di ogni tipo di lavoro e ne fa un collo di bottiglia. Le dimensioni in pixel non stimano il costo di un modello, di una texture o di un contenitore multipagina. E la formulazione "costi misurati, non stimati" della revisione precedente descriveva qualcosa di impossibile: per ammettere un lavoro prima di eseguirlo bisogna stimarlo — la misura serve a **calibrare** la stima, non a sostituirla. Una media, per quanto misurata, non protegge dall'immagine anomala che consuma molte volte il normale. *Conseguenza:* nessun componente avvia lavoro fuori dalle code; stime, margini e limite per elemento sono parametri prodotti dal cancello n°1 e rivedibili con la misura a posteriori; **l'ampiezza della banda di ritenzione è un parametro del budget** e va calibrata insieme ad esso; il test di lunga durata è parte del contratto.
- **ADR-010 — Le regole sono dati, non codice.** *Decisione:* pattern di rinomina e regole di smistamento come strutture serializzabili con grammatica dichiarata. *Motivo:* rende possibili preset, condivisione e cartelle intelligenti senza riscrivere il motore. *Conseguenza:* la grammatica dei token va specificata e versionata (FR-032/FR-038).
- **ADR-011 — Identità dalle primitive di sistema; conservazione dei giudizi come matrice di casi, non come promessa.** *Decisione:* l'identità si costruisce sulle chiavi di risorsa che il sistema espone — identificatore di risorsa, di documento, di volume — più i bookmark come forma persistente, nella combinazione stabilita dal cancello n°2. La **validità** resta `mtime + size` e la sua scadenza non tocca mai i giudizi. L'hash è **recupero best-effort su materiale già indicizzato**, non identità. Al posto della promessa "i giudizi sopravvivono agli spostamenti esterni" il documento pubblica una **matrice esplicita** che classifica ogni caso come supportato, best-effort o non supportato (FR-054). *Motivo:* `volume + inode` era una formulazione artigianale al posto di primitive esistenti con proprietà note; l'hash era giustificato come "già calcolato" mentre i duplicati lo calcolano per intero solo su collisione, e comunque due duplicati esatti lo condividono; e se l'utente sposta la sola immagine, il sidecar resta indietro e nessun meccanismo può recuperare quel caso. *Conseguenza:* la matrice è contenuto di prodotto visibile e non una nota tecnica; l'hash si calcola quando è già necessario per altro; le primitive restano un'ipotesi finché il cancello n°2 non le verifica.
- **ADR-012 — Eventi come suggerimento, riconciliazione come verità, avvio garantito e completamento no.** *Decisione:* l'osservatore non aggiorna mai il catalogo dal contenuto di un evento: raccoglie, smorza in una **finestra di quiete**, coalesce per ambito, e attiva un **riconciliatore** che rienumera e calcola la differenza. Oltre al debounce esiste un tempo massimo entro il quale la riconciliazione viene **avviata**, anche se gli eventi continuano ad arrivare; il suo I/O è **annullabile e soggetto a scadenza**, e l'interfaccia espone lo **stato di freschezza** — aggiornata, aggiornamento in corso, potenzialmente obsoleta, volume non disponibile. Sono esclusi i file di servizio, i temporanei, i nascosti e **le scritture prodotte dall'app stessa**. L'identificatore d'evento è persistito **legato all'UUID del volume**; identificatori eliminati o riavvolti, volumi smontati o ripristinati, cambio della radice e segnalazioni di eventi persi portano alla riconciliazione completa. Su volumi di rete e cartelle sincronizzate i file non materializzati sono mostrati come tali e mai scaricati implicitamente, e **classi di volume diverse possono richiedere meccanismi diversi**. *Motivo:* l'infrastruttura di notifica è rumorosa, coalescente e lacunosa sotto carico. La sola finestra di quiete ha un difetto proprio — una raffica continua non la raggiunge mai — ma il tempo massimo introdotto per correggerlo ne aveva uno simmetrico: su un volume di rete bloccato o un servizio di sincronizzazione non disponibile **nessun limite può garantire che l'operazione termini**. Promettere un aggiornamento entro un tempo massimo sarebbe stata l'ennesima garanzia non mantenibile; promettere l'avvio, e dire onestamente quando la vista può essere obsoleta, è ciò che il sistema può reggere. *Conseguenza:* il costo di una raffica è limitato a una riconciliazione per finestra e l'attesa massima prima del **tentativo** è dichiarata; gli stati di freschezza sono requisiti funzionali e non note tecniche; la correttezza della vista non dipende mai dalla completezza degli eventi; e il cancello n°2 ha mandato esplicito di concludere che alcune classi di volume richiedono riconciliazione periodica, aggiornamento manuale o supporto dichiarato come limitato.
- **ADR-013 — Giudizi in sidecar XMP, con coordinamento cooperativo e difesa a più livelli.** *Decisione:* stelle ed etichette sono scritte in un `.xmp` accanto all'immagine, in formato standard. La scrittura è **atomica sul singolo file**, **conservativa** sui campi sconosciuti, e coordinata con il meccanismo di sistema. Poiché quel coordinamento vincola solo le applicazioni che vi partecipano, la protezione è a quattro livelli: **controllo della versione osservata dentro l'accesso coordinato**, **verifica dopo la sostituzione**, **conservazione temporanea della versione precedente**, e **recupero esplicito** quando si rileva una scrittura concorrente non coordinata. Ogni immagine ha uno **stato di sincronizzazione** — allineato, scrittura in attesa, scrittura fallita, conflitto esterno — custodito in `DurableState`, che insieme al sidecar è la sede autorevole. Il file immagine non viene mai aperto in scrittura per un giudizio. La scrittura è disattivabile; su cartelle non scrivibili si degrada allo stato locale, dichiarandolo. *Motivo:* i giudizi devono sopravvivere alla perdita della cache, al cambio di Mac e alla disinstallazione, ed essere leggibili dagli strumenti che l'utente già usa. "Rileggo e riscrivo invariato ciò che non conosco" non protegge da chi scrive tra la nostra lettura e la nostra sostituzione, e "vince la fonte più recente" non è una politica ma una speranza. Ma la correzione introdotta con il coordinamento di sistema era a sua volta troppo forte: quel meccanismo è **cooperativo, non impositivo**, e uno strumento che lo ignora entra comunque nella finestra. Terza occorrenza dello stesso difetto di scrittura — dopo il filesystem e il sidecar — e la ragione per cui è ora una regola dichiarata. *Conseguenza:* servono decisioni che una specifica non fornisce — convenzione di nome, collisione tra due immagini con la stessa radice e formati diversi, rappresentazione dello scarto (candidato: `xmp:Rating = -1`, più uniforme di `xmp:Label`) — e nessuna è chiusa finché il cancello n°3 non produce un round-trip su strumenti reali, **che deve deliberatamente includere uno scrittore non coordinato**. Il contratto verso l'utente è conflitto visibile e recuperabilità, mai atomicità.
- **ADR-014 — Punteggi come euristiche dichiarate e versionate.** *Decisione:* lo stato aperto/chiuso degli occhi è un'**euristica costruita sui landmark**, non un risultato del sistema: dichiarata come tale, calibrata, e accompagnata dalla sua affidabilità stimata. Il punteggio di qualità di cattura del volto è **olistico** e si sovrappone a nitidezza ed esposizione calcolate separatamente: la sovrapposizione è misurata e **dichiarata all'utente**, e il ruolo di quel punteggio nella cascata è deciso di conseguenza. Ogni punteggio memorizzato porta con sé **revisione della visione artificiale, versione del modello, preprocessing, algoritmo e soglie**. *Motivo:* presentare un'euristica nostra come capacità di sistema è un errore di categoria che si paga sulla calibrazione; mostrare due criteri sovrapposti come ragioni indipendenti è una ripetizione travestita da conferma, e colpisce il differenziatore n°3, che è la spiegabilità; e senza versionamento il primo aggiornamento di sistema rende i punteggi in cache silenziosamente incomparabili. *Conseguenza:* i punteggi si invalidano al cambio di una qualunque delle versioni registrate; l'interfaccia deve poter dire "calcolato con una versione precedente"; la cascata va rivista alla luce della sovrapposizione misurata.
- **ADR-015 — Cancelli tecnici prima del full build, e consegna a tappe.** *Decisione:* quattro verifiche precedono la costruzione completa — scala e memoria su 50.000 file; eventi e identità su APFS, volume esterno, cartella sincronizzata e volume di rete; round-trip XMP con strumenti reali e uno scrittore non coordinato; iniezione di arresti in ogni punto di un lotto. Ognuna produce un esito scritto che conferma o modifica gli ADR corrispondenti, e **ognuna può concludere che qualcosa non è supportabile**. Lo scope non è ridotto, ma la costruzione segue quattro tappe consegnabili una per volta. *Motivo:* tre revisioni indipendenti hanno osservato che l'insieme è più vicino a una prima versione professionale che a un minimo prodotto, e che dichiarare il costo affronta il rischio di sforzo ma non quello di **integrazione**. Ognuno dei quattro cancelli può invalidare un ADR, e scoprirlo dopo aver costruito sopra costa molte volte tanto. *Conseguenza:* l'inizio della costruzione completa è subordinato all'esito dei cancelli, ed è un ritardo dichiarato e voluto; gli ADR-007, 009, 011, 012 e 013 sono formalmente **provvisori** fino al cancello corrispondente; ogni tappa deve essere consegnabile da sola. Con la revisione 1.3 le revisioni sulla carta si chiudono: le domande rimaste non si chiudono rileggendo il documento ma misurando.
- **ADR-016 — I file sono dati non fidati; il rischio di decodifica è accettato e dichiarato.** *Decisione:* per l'MVP l'app resta **monoprocesso**: decodifica, lettura metadati e analisi di immagini che l'utente non ha prodotto avvengono nello stesso processo che ha accesso ai suoi file. Il rischio è **dichiarato e accettato**, non ignorato, e accompagnato dalle difese disponibili senza costo: hardened runtime e validazione delle librerie già previsti dalla distribuzione firmata, nessun percorso che interpreti il contenuto di un file come codice, nessuna esecuzione di contenuto incorporato, errori di decodifica contenuti e segnalati senza compromettere il caricamento della cartella, e un corpus di file malformati nei test di integrazione continua. L'**isolamento di decodifica e analisi in un processo separato** è registrato come funzione di crescita, con l'innesto già collocato nell'architettura affinché introdurlo non richieda di rivedere i confini dei componenti. *Motivo:* `Access` è un buon confine **di codice** ma non è un confine **di sicurezza**: non riduce i privilegi del processo e non contiene un difetto in un decodificatore di sistema, che girerebbe con tutti i privilegi dell'app su un'app non in sandbox con accesso ai file dell'utente. E non è uno scenario ipotetico: Adalgisa riceve ogni settimana cartelle prodotte da persone e apparecchi che non controlla, quindi il materiale non fidato è il flusso di lavoro settimanale di una delle due persone. Il documento dichiarava che nessuna immagine lascia il dispositivo e non diceva nulla su cosa accade quando un'immagine malformata **entra**. *Conseguenza:* il rischio residuo è scritto e riesaminabile invece che invisibile; l'isolamento non è nell'MVP perché attraverserebbe la parte più sensibile alla latenza — il rischio primario del prodotto — e aggiungerebbe un confine di processo a uno scope già giudicato ampio da tre revisioni; la decisione va rivista se emergono episodi reali o se il costo dell'isolamento risulta basso alla misura.

---

## Functional Requirements

<!-- archetipo:prd section=functional_requirements required=true -->

### Area 1 - Apertura e navigazione delle cartelle

- **FR-001** L'utente può aprire una cartella trascinandola sull'app o sulla sua icona, tramite il dialogo di apertura di sistema, dalle cartelle recenti o dai preferiti nella barra laterale.
- **FR-002** La vista mostra **esclusivamente** i file riconosciuti come immagini secondo il tipo di sistema (`UTType`), non secondo l'estensione.
- **FR-003** L'app indica quanti elementi non-immagine sono presenti nella cartella, senza mescolarli mai al contenuto visibile, distinguendo i **file collegati** (sidecar delle immagini presenti) dal resto del contenuto estraneo.
- **FR-004** L'utente può ordinare per nome, data di scatto, data di modifica, dimensione file e rating, in ordine crescente o decrescente, e l'ordinamento persiste tra le sessioni.
- **FR-005** L'app ricorda le cartelle aperte di recente e permette di fissare cartelle preferite nella barra laterale; i riferimenti sono persistiti in forma che resta valida quando la cartella viene rinominata o spostata sullo stesso volume, e che segnala esplicitamente quando non è più risolvibile.

### Area 2 - Osservazione della cartella e freschezza della vista

- **FR-006** L'app rileva le modifiche alla cartella aperta (file aggiunti, rimossi, rinominati, modificati da altre applicazioni) e aggiorna la vista senza intervento dell'utente, **senza perdere la selezione corrente** né la posizione di scorrimento.
- **FR-007** Gli eventi del filesystem non aggiornano mai direttamente il catalogo: attivano una **riconciliazione** che rienumera l'ambito interessato e ne calcola la differenza rispetto allo stato conosciuto. La vista riflette sempre il risultato della riconciliazione, mai il contenuto grezzo di un evento.
- **FR-008** Gli eventi sono smorzati in una **finestra di quiete** e coalescenti per ambito: una raffica di modifiche entro la finestra produce **una sola** riconciliazione. Un file ancora in scrittura è considerato solo quando dimensione e data di modifica si sono stabilizzate.
- **FR-009** Esiste un tempo massimo entro il quale una riconciliazione viene **avviata**, anche se gli eventi continuano ad arrivare senza interruzione. L'app non promette che la riconciliazione si **concluda** entro un limite, perché su un volume non disponibile ciò non è possibile.
- **FR-010** L'I/O della riconciliazione è annullabile e soggetto a scadenza: una riconciliazione che non progredisce non blocca l'interazione, non accumula tentativi sovrapposti e viene interrotta anziché restare appesa.
- **FR-011** L'app mostra sempre lo **stato di freschezza della vista** con almeno quattro condizioni distinte: aggiornata, aggiornamento in corso, potenzialmente obsoleta, volume non disponibile. L'utente può richiedere un aggiornamento manuale in qualunque momento.
- **FR-012** L'app ignora i file di servizio del sistema, i temporanei e di trasferimento incompleto, i nascosti e **le scritture prodotte dall'app stessa** — in particolare i sidecar appena salvati — così che nessuna provochi aggiornamenti o consumo di risorse.
- **FR-013** L'app gestisce esplicitamente le condizioni in cui la cronologia degli eventi non è affidabile: segnalazione di eventi persi, identificatori eliminati o riavvolti, cambio della cartella osservata. In ognuna riconcilia integralmente l'ambito senza perdere selezione, giudizi né risultati già calcolati.
- **FR-014** L'identificatore dell'ultimo evento elaborato è persistito **insieme all'identità del volume** e non viene applicato a un volume diverso. Smontaggio, rimontaggio o ripristino portano a riconciliazione anziché a interpretazione di identificatori non più validi.
- **FR-015** Le modifiche avvenute mentre l'app era chiusa sono rilevate alla riapertura riprendendo dagli eventi quando disponibili e riconciliando in ogni caso; l'utente non deve mai svuotare la cache per vedere la cartella aggiornata.
- **FR-016** Su volumi di rete e cartelle gestite da servizi di sincronizzazione, i file non ancora materializzati sono mostrati come tali e **non vengono scaricati implicitamente**: nessuna operazione di sola visualizzazione provoca un trasferimento non richiesto.
- **FR-017** Classi di volume diverse possono usare meccanismi di aggiornamento diversi — notifiche, riconciliazione periodica, aggiornamento manuale. Dove il supporto è limitato, l'app **lo dichiara sulla cartella aperta** invece di comportarsi come se fosse completo.
- **FR-018** L'osservazione è attiva sulla sola cartella aperta, non discende ricorsivamente nelle sottocartelle, ed è sospesa quando nessuna cartella è aperta.

### Area 3 - Visualizzazione

- **FR-019** La griglia mostra le anteprime con dimensione della cella regolabile su almeno cinque livelli, fino a permettere di valutare la nitidezza senza aprire l'immagine.
- **FR-020** La griglia resta fluida durante lo scorrimento su cartelle di almeno 10.000 immagini, caricando le anteprime di ciò che è visibile e imminente e liberando ciò che è ampiamente fuori vista.
- **FR-021** L'utente può aprire un'anteprima grande dell'immagine selezionata, a pannello o a schermo intero, con un solo tasto.
- **FR-022** Nell'anteprima grande l'utente può ingrandire fino alla scala 1:1 dei pixel e spostarsi nell'immagine, per valutare fuoco e dettaglio.
- **FR-023** Le immagini sono visualizzate rispettando l'orientamento EXIF e il profilo colore incorporato.
- **FR-024** L'app segnala visivamente le immagini per cui non è possibile generare un'anteprima o leggere il contenuto — file troncati, corrotti, di formato inatteso — **senza interrompere il caricamento delle altre** e senza che l'errore si propaghi al resto della cartella.

### Area 4 - Navigazione da tastiera

- **FR-025** L'utente può spostare la selezione con i soli tasti freccia, sia in griglia (movimento bidimensionale) sia in anteprima grande (immagine precedente e successiva).
- **FR-026** L'utente può estendere la selezione da tastiera, selezionare tutto e invertire la selezione.
- **FR-027** Tutte le azioni dell'MVP — anteprima grande, pannello metadati, rating, marcatura, spostamento nel Cestino, rinomina, avvio dell'analisi — sono attivabili da tastiera senza usare il mouse.
- **FR-028** L'app espone un pannello di aiuto che elenca tutte le scorciatoie attive, richiamabile con un tasto.

### Area 5 - Metadati

- **FR-029** Un pannello metadati, mostrabile e nascondibile con un tasto, presenta per l'immagine selezionata: nome e percorso, dimensione del file, dimensioni in pixel, formato, date di creazione e modifica, spazio colore.
- **FR-030** Lo stesso pannello mostra i dati EXIF disponibili — fotocamera, obiettivo, ISO, tempo, diaframma, focale, data e ora di scatto, orientamento — e i dati IPTC e GPS quando presenti, indicando esplicitamente i campi assenti anziché ometterli silenziosamente.
- **FR-031** Il pannello si aggiorna al cambio di selezione senza latenza percepibile; con selezione multipla mostra i valori comuni e segnala i divergenti. L'utente può copiare un singolo campo o l'intero blocco.

### Area 6 - Rinomina massiva (capacità a)

- **FR-032** L'utente può rinominare una selezione applicando un pattern composto da testo libero e token. I token supportati nell'MVP sono almeno:

  | Token | Significato | Comportamento se il dato manca |
  |---|---|---|
  | `{nome}` | nome originale senza estensione | mai assente |
  | `{data:formato}` | data di scatto EXIF, con formato specificato (es. `yyyy-MM-dd`) | ricade sulla data di modifica del file, marcata come ricaduta nell'anteprima |
  | `{ora:formato}` | ora di scatto EXIF | come sopra |
  | `{fotocamera}` | marca e modello | sostituito da segnaposto configurabile |
  | `{obiettivo}` | modello di obiettivo | sostituito da segnaposto configurabile |
  | `{iso}`, `{tempo}`, `{diaframma}`, `{focale}` | parametri di scatto | sostituito da segnaposto configurabile |
  | `{larghezza}`, `{altezza}` | dimensioni in pixel | mai assente |
  | `{contatore:cifre}` | contatore progressivo con riempimento a zeri | mai assente |
  | `{cartella}` | nome della cartella contenente | mai assente |

- **FR-033** L'app mostra **obbligatoriamente** un'anteprima `nome attuale → nome nuovo` per ogni file coinvolto prima di eseguire qualsiasi rinomina, evidenziando collisioni, caratteri non ammessi, nomi troppo lunghi e ricadute su dati mancanti.
- **FR-034** L'utente sceglie esplicitamente la politica per le collisioni: suffisso progressivo, salto del file, o annullamento del lotto. Il valore predefinito non sovrascrive mai un file esistente.
- **FR-035** L'estensione originale è preservata e non è modificabile dal pattern.
- **FR-036** Ogni lotto di rinomina è registrato prima dell'esecuzione ed è annullabile anche dopo la chiusura e riapertura dell'app, con il contratto e gli esiti di FR-077 e FR-078.

### Area 7 - Smistamento in sottocartelle (capacità b)

- **FR-037** L'utente può generare sottocartelle e spostarvi le immagini secondo una regola scelta tra: data di scatto (anno, anno-mese, anno-mese-giorno), fotocamera, formato, rating, marcatura da scartare.
- **FR-038** Il nome delle sottocartelle è definibile con la stessa grammatica di token della rinomina massiva.
- **FR-039** L'app mostra obbligatoriamente l'anteprima dell'albero risultante — quali cartelle verranno create e quanti file finiranno in ciascuna — prima di eseguire qualsiasi spostamento.
- **FR-040** Le immagini per cui la regola non è applicabile finiscono in una cartella di raccolta con nome configurabile, e non restano mai in stato indeterminato.
- **FR-041** Anche lo smistamento è registrato e annullabile con lo stesso contratto della rinomina (FR-036).
- **FR-042** Nell'MVP le operazioni massive agiscono sulla cartella corrente e non discendono ricorsivamente nelle sottocartelle; il limite è dichiarato in interfaccia.

### Area 8 - Giudizio, marcatura e filtri

- **FR-043** L'utente può assegnare un rating da 1 a 5 stelle, rimuoverlo, e marcare o smarcare un'immagine come "da scartare", con un singolo tasto e senza lasciare la posizione corrente.
- **FR-044** L'interfaccia risponde immediatamente, senza attendere il disco. La **prima scrittura durevole** è quella nello stato locale: finché non riesce il giudizio non è considerato accettato, e l'app lo segnala invece di lasciar credere che sia salvato.
- **FR-045** L'utente può filtrare per rating (minimo, esatto), marcatura, formato e intervallo di date, e combinare i filtri.

### Area 9 - Durabilità e portabilità dei giudizi

- **FR-046** Rating e marcature sono scritti in un **sidecar XMP** affiancato all'immagine, in formato standard leggibile dai principali strumenti fotografici, oltre a essere mantenuti nello stato locale.
- **FR-047** L'app **non apre mai in scrittura il file immagine** per registrare un giudizio. La scrittura del sidecar è atomica sul singolo file: un'interruzione non può produrre un sidecar parziale né alterare l'immagine.
- **FR-048** La scrittura del sidecar è coordinata con le altre applicazioni tramite il meccanismo di sistema, con il controllo della versione osservata **all'interno** dell'accesso coordinato e una **verifica successiva alla scrittura**; la versione precedente è conservata temporaneamente per permettere il recupero.
- **FR-049** Poiché il coordinamento vincola solo le applicazioni che vi partecipano, l'app **rileva e dichiara** le scritture concorrenti non coordinate anziché ignorarle, offre il recupero del valore precedente, e in nessun caso sovrascrive in silenzio.
- **FR-050** Ogni immagine ha uno **stato di sincronizzazione esplicito e visibile** — allineato, scrittura in attesa, scrittura fallita, conflitto esterno — con l'indicazione di cosa lo ha determinato. Nessun conflitto viene risolto in silenzio.
- **FR-051** L'ordine di autorità è dichiarato e osservabile: **stato locale durevole e sidecar prevalgono**, la cache derivata può restare indietro ed è riallineata. In caso di divergenza la cache non è mai la fonte.
- **FR-052** Alla lettura, l'app riconosce i sidecar già presenti, compresi quelli prodotti da altri strumenti, e ne importa rating ed etichetta. I campi che non conosce sono **conservati invariati** quando riscrive il file.
- **FR-053** Ogni operazione su file include il sidecar nel piano del lotto, nella sua anteprima e nel suo registro, e lo ripristina insieme all'immagine in caso di annullamento. Un'interruzione può lasciare immagine e sidecar in posizioni diverse: in quel caso l'app lo rileva e lo riporta invece di nasconderlo.
- **FR-054** L'app pubblica, in interfaccia e non solo in documentazione, la **matrice dei casi** di conservazione del giudizio, con tre livelli espliciti:

  | Caso | Livello |
  |---|---|
  | Rinomina o spostamento eseguiti dall'app | supportato |
  | Rinomina nella cartella osservata, con sidecar presente accanto | supportato |
  | Immagine e sidecar spostati insieme in un'altra cartella poi aperta nell'app | supportato |
  | Salvataggio atomico dell'immagine da un'altra applicazione, sidecar intatto | supportato |
  | Copia dell'immagine con il suo sidecar | supportato |
  | Immagine spostata da sola, sidecar lasciato indietro | **non supportato** |
  | Immagine spostata su un altro volume senza sidecar | **non supportato** |
  | Immagine con contenuto modificato e sidecar assente | **non supportato** |
  | Immagine ritrovata in una cartella già indicizzata, senza sidecar | recupero best-effort |
  | Sidecar orfano, immagine corrispondente non trovata | recupero best-effort, segnalato |

- **FR-055** Il recupero best-effort si applica solo a materiale già presente nella cache e non comporta in nessun caso la lettura integrale anticipata dell'intera cartella. L'app dichiara quando un'associazione è stata ricostruita per tentativo anziché per collegamento diretto.
- **FR-056** La scrittura dei sidecar è disattivabile dalle impostazioni. Quando la cartella non è scrivibile, i giudizi restano nello stato locale e l'app dichiara che su quella cartella non sono portabili, senza presentarlo come un errore.
- **FR-057** L'interfaccia dichiara in modo comprensibile dove vivono i giudizi, cosa comporta disattivare i sidecar, e quale parte dello stato locale il comando di svuotamento **non** tocca.

### Area 10 - Duplicati

- **FR-058** L'app individua i **duplicati esatti** all'interno della selezione o della cartella corrente, procedendo per stadi di costo crescente e senza leggere integralmente file che possono essere esclusi prima.
- **FR-059** I duplicati esatti sono presentati in gruppi con un candidato da tenere proposto secondo criteri dichiarati (percorso più stabile, nome più informativo, data più antica, presenza di un giudizio già assegnato), sempre modificabile dall'utente.
- **FR-060** L'app individua i **gruppi di quasi-duplicati** combinando similarità visiva e vicinanza temporale, con soglia regolabile e riorganizzazione visiva immediata al variare della soglia.
- **FR-061** Nessun duplicato viene eliminato senza conferma esplicita; l'eliminazione passa dal Cestino di macOS.

### Area 11 - Selezione assistita (capacità c)

- **FR-062** Data una selezione, l'utente può chiedere le **N migliori da tenere** (N predefinito 3, regolabile almeno tra 1 e 10).
- **FR-063** L'analisi procede nell'ordine stabilito: (1) raggruppamento per similarità visiva e temporale, (2) valutazione del soggetto — volti rilevati, qualità del volto, stima di occhi aperti o chiusi, (3) qualità tecnica misurabile — nitidezza valutata sul soggetto, mosso, esposizione e clipping, rumore stimato, (4) punteggio estetico come spareggio finale.
- **FR-064** Per **ogni** immagine valutata l'app mostra il punteggio scomposto nei criteri che lo compongono, in forma leggibile, e non un singolo numero opaco.
- **FR-065** Dove due criteri si sovrappongono — in particolare il punteggio complessivo del volto rispetto a nitidezza ed esposizione calcolate separatamente — l'app **dichiara la sovrapposizione** invece di presentarli come conferme indipendenti, e non conta due volte la stessa grandezza nella graduatoria.
- **FR-066** La stima di occhi aperti o chiusi è presentata come **valutazione dell'app con affidabilità dichiarata**, non come dato certo, ed è verificabile dall'utente sull'anteprima grande.
- **FR-067** L'app dichiara sempre **perché** un'immagine è stata proposta e perché un'altra è stata scartata, in termini di criteri, così che l'utente possa dissentire con cognizione.
- **FR-068** Ogni punteggio memorizzato porta con sé la versione degli strumenti che lo hanno prodotto — revisione della visione artificiale, versione del modello, preprocessing, algoritmo e soglie. Al cambiare di una di esse i punteggi non sono più considerati validi e l'app lo indica anziché confrontare valori incomparabili.
- **FR-069** L'utente può modificare la proposta prima di agire, e nessuna immagine viene eliminata o spostata senza conferma esplicita.
- **FR-070** L'analisi è eseguita **solo su richiesta e solo su una selezione**: aprire una cartella non innesca in nessun caso il calcolo dei punteggi.
- **FR-071** L'analisi è annullabile in qualunque momento, mostra un avanzamento leggibile, e i risultati parziali restano validi e memorizzati.
- **FR-072** Tutta l'analisi avviene in locale: nessuna immagine, nessun dato derivato e nessun metadato lascia il dispositivo in nessuna circostanza.

### Area 12 - Editing di base

- **FR-073** L'utente può ruotare un'immagine di 90° in entrambi i versi e capovolgerla orizzontalmente e verticalmente, anche su selezioni multiple.
- **FR-074** L'utente può ritagliare con proporzioni libere o predefinite (1:1, 4:3, 3:2, 16:9), con riquadro trascinabile e valori visibili.
- **FR-075** Al salvataggio l'utente sceglie esplicitamente tra sovrascrivere l'originale e creare una copia; l'opzione predefinita è la copia. Creando una copia, il giudizio dell'immagine di partenza è replicato sulla copia insieme al suo sidecar.
- **FR-076** Il salvataggio preserva i metadati EXIF/IPTC di partenza, aggiornando i soli campi resi incoerenti dalla trasformazione (dimensioni, orientamento).

### Area 13 - Operazioni su file e reversibilità

- **FR-077** Ogni lotto segue un contratto dichiarato: piano e precondizioni registrati prima di agire, **precondizioni ricontrollate immediatamente prima dell'esecuzione** e non solo al momento dell'anteprima, passi eseguiti in modo idempotente e registrati uno a uno. Un'interruzione in qualunque punto lascia il lotto in uno stato riconoscibile. Il contratto è: *l'app riconosce sempre lo stato raggiunto, tenta ripresa o compensazione, e dichiara esplicitamente ciò che richiede intervento umano.* Non promette che un lotto sia indivisibile né che sia sempre concludibile.
- **FR-078** Ogni lotto termina in uno di **cinque esiti dichiarati e visibili all'utente**: completato, compensato, parzialmente recuperato, bloccato in attesa di una decisione dell'utente, abbandonato dall'utente. Un lotto bloccato resta visibile nella cronologia finché l'utente non lo risolve o non lo abbandona esplicitamente.
- **FR-079** L'app distingue **errore locale** ed **errore sistemico**. Un errore su un singolo file — permesso mancante su quel file, nome non valido, file scomparso — lo fa saltare e il lotto prosegue con un esito riportato. Un errore sistemico — volume scomparso, permessi revocati sull'intera cartella, spazio esaurito — **sospende il lotto** invece di ripetersi su ogni file rimanente.
- **FR-080** Se tra l'anteprima e l'esecuzione le precondizioni sono cambiate — file spostati, rinominati, resi non scrivibili, o comparsi con lo stesso nome di destinazione — l'app **interrompe prima di agire** e ripresenta l'anteprima aggiornata, invece di procedere su un piano non più valido.
- **FR-081** L'utente può spostare, copiare e rinominare singole immagini e selezioni verso una destinazione scelta, con gestione esplicita delle collisioni.
- **FR-082** L'eliminazione avviene **sempre tramite il Cestino di macOS** e mai con cancellazione diretta. L'app dichiara che il ripristino dal Cestino resta nelle mani dell'utente e del sistema: l'elemento vi viene spostato, ma l'app non può promettere che vi rimanga.
- **FR-083** L'app espone una cronologia delle operazioni massive, con la possibilità di annullare un lotto specifico e non solo l'ultimo. L'annullamento dichiara esattamente cosa ha ripristinato e cosa non ha potuto ripristinare, e perché.
- **FR-084** Ogni operazione riporta un esito esplicito: quanti file elaborati, saltati, in errore e per quale motivo, e con quale dei cinque esiti si è chiuso il lotto.
- **FR-085** L'utente può rivelare qualsiasi immagine nel Finder e aprirla con un'altra applicazione, senza perdere lo stato dell'app.

### Area 14 - Archivi locali, identità e prestazioni

- **FR-086** L'app mantiene **due archivi locali distinti**: una **cache derivata**, che contiene solo dati ricalcolabili dai file, e uno **stato durevole**, che contiene il registro delle operazioni, i lotti non completati, i giudizi non ancora scritti nei sidecar o con scrittura fallita, e lo stato di sincronizzazione.
- **FR-087** Il comando di svuotamento agisce **esclusivamente sulla cache derivata**. Lo stato durevole non è cancellabile dall'interfaccia, e l'app dichiara prima dell'operazione cosa viene eliminato e cosa resta.
- **FR-088** All'avvio l'app verifica l'integrità dello stato durevole. Se lo trova danneggiato, **recupera ciò che è recuperabile, mette in quarantena il resto e lo dichiara all'utente** con l'indicazione di cosa è andato perso, invece di ripartire in silenzio da uno stato vuoto.
- **FR-089** La cronologia delle operazioni ha una **politica di retention dichiarata**: l'app indica per quanto un lotto resta annullabile e non lascia crescere il registro senza limite. La potatura non rimuove mai un lotto non completato o bloccato.
- **FR-090** Quando lo spazio su disco non è sufficiente a garantire una scrittura durevole, l'app **rifiuta l'operazione e lo dichiara** invece di procedere e fallire a metà.
- **FR-091** L'archivio distingue **identità** e **validità** come informazioni separate: l'identità determina a chi appartengono i giudizi, la validità determina cosa va ricalcolato. La scadenza della validità invalida i dati derivati e **non tocca mai i giudizi**.
- **FR-092** Alla riapertura di una cartella già indicizzata, la griglia è popolata dalla cache senza ricalcoli, e le modifiche avvenute nel frattempo sono riconciliate in sottofondo senza bloccare l'interazione.
- **FR-093** Il caricamento in sottofondo mantiene una **banda attorno alla parte visibile**, con soglie di entrata e uscita diverse, in modo che un piccolo movimento di scorrimento non provochi la perdita e il ricalcolo del lavoro appena svolto.

### Area 15 - Permessi e primo avvio

- **FR-094** L'app non richiede l'Accesso completo al disco per funzionare, e non ne fa un prerequisito di primo avvio: l'utente apre una cartella e lavora.
- **FR-095** Ogni richiesta di accesso avviene **dopo il gesto che la motiva** — l'apertura o il trascinamento di una cartella — e mai su una schermata preliminare; la motivazione mostrata nel dialogo di sistema spiega in una frase perché serve.
- **FR-096** Se l'accesso viene negato, l'app mostra uno stato che spiega cosa manca e come concederlo, con una via diretta al pannello di sistema corrispondente, e resta pienamente utilizzabile sulle cartelle già accessibili.
- **FR-097** L'app offre, come opzione e non come obbligo, la concessione dell'Accesso completo al disco per chi lavora su percorsi insoliti, spiegando cosa cambia in concreto.

### Area 16 - Accessibilità

- **FR-098** Ogni funzione dell'MVP è raggiungibile da tastiera; nessuna azione richiede esclusivamente il mouse o il trackpad.
- **FR-099** Le immagini in griglia, i controlli e i campi del pannello metadati espongono etichette leggibili da VoiceOver; il valore dei metadati, il giudizio assegnato, il suo stato di sincronizzazione e lo stato di freschezza della vista sono annunciabili senza aprire finestre aggiuntive.
- **FR-100** L'app rispetta le preferenze di sistema *Riduci movimento* e *Aumenta contrasto*, e supporta la dimensione del testo di sistema nei pannelli senza troncamenti.

---

## Non-Functional Requirements

<!-- archetipo:prd section=non_functional_requirements required=true -->

### Prestazioni e reattività

Sono i requisiti che governano il rischio primario del prodotto e vanno trattati come vincoli, non come obiettivi. I valori numerici sono **soglie dichiarate da confermare dal cancello tecnico n°1**, non misure già ottenute.

- **NFR-P1** Alla prima apertura di una cartella con 3.000 immagini, la prima schermata di anteprime è visibile entro **1 secondo**; la griglia è navigabile mentre il resto continua a caricarsi in sottofondo.
- **NFR-P2** Alla riapertura di una cartella già indicizzata la griglia è popolata **immediatamente** dalla cache; l'eventuale riconciliazione avviene in sottofondo e non ritarda la prima schermata.
- **NFR-P3** Lo spostamento della selezione con le frecce risponde entro **100 ms** anche mentre sono in corso lavori in sottofondo; l'interfaccia non si blocca mai.
- **NFR-P4** Il pannello metadati si aggiorna entro **150 ms** dal cambio di selezione.
- **NFR-P5** Nessuna scansione bloccante all'apertura di una cartella: enumerazione, metadati, hash e analisi visiva sono lavori annullabili a priorità inferiore all'interazione.
- **NFR-P6** Il lavoro in sottofondo relativo a ciò che è **ampiamente fuori** dalla parte visibile è annullato, mantenendo una banda di ritenzione con soglie di entrata e uscita distinte; la coda non cresce indefinitamente con lo scorrimento, e un piccolo movimento non provoca la perdita del lavoro appena svolto.
- **NFR-P7** L'occupazione di memoria resta stabile su cartelle da 10.000 immagini: le anteprime sono liberate al di fuori della banda di ritenzione.
- **NFR-P8** Il rilevamento dei duplicati esatti su 10.000 file non legge integralmente i file che possono essere esclusi negli stadi precedenti. Nessun hash è calcolato in anticipo sull'intera cartella per scopi diversi dal rilevamento richiesto.
- **NFR-P9 Tetto di memoria dichiarato e verificato.** Esiste un limite superiore dichiarato all'occupazione di picco su una cartella da 50.000 immagini con scorrimento continuo, e una sessione di lunga durata non mostra crescita monotona. Entrambe le soglie sono verificate da un test automatico che fallisce la build quando vengono superate.
- **NFR-P10 Il parallelismo è derivato da stime conservative calibrate.** Il lavoro passa da code specializzate per tipo, ammesse entro un budget di memoria comune. Poiché l'ammissione precede l'esecuzione, il costo è **stimato**: le stime sono conservative, segmentate per tipo di lavoro, formato, classe di risoluzione e hardware, **calibrate su misure reali**, dotate di margine di sicurezza, corrette dalla misura a posteriori, e affiancate da un **limite per singolo elemento** che interrompe l'elemento anomalo anziché il processo. Il budget si riduce sotto pressione di memoria. Nessuna immagine viene decodificata a piena risoluzione quando ne basta una ridimensionata.
- **NFR-P11 Quiete a riposo e avvio garantito della riconciliazione.** Con una cartella aperta e ferma, l'uso di CPU è indistinguibile da zero. Una raffica produce **al massimo una riconciliazione per finestra di quiete**, e almeno un **tentativo avviato** entro il tempo massimo dichiarato anche se la raffica non si interrompe. Il **completamento** non è oggetto di garanzia: su un volume non disponibile l'app interrompe il tentativo e dichiara lo stato della vista.
- **NFR-P12 La banda di ritenzione è un parametro del budget.** La sua ampiezza è memoria occupata di proposito e viene calibrata insieme al budget, non scelta indipendentemente come costante dell'interfaccia.

### Affidabilità e integrità dei dati

- **NFR-A1** Nessuna operazione distruttiva senza conferma esplicita; nessuna eliminazione fuori dal Cestino di macOS.
- **NFR-A2** Ogni operazione massiva è preceduta da un'anteprima completa, da un **ricontrollo delle precondizioni immediatamente prima di agire**, e da una registrazione persistente che ne consente ripresa o compensazione dopo un riavvio. Il registro include i file collegati mossi insieme alle immagini.
- **NFR-A3 Il contratto è la recuperabilità, non l'atomicità né la conclusione garantita.** L'app non dichiara in nessun punto che un insieme di file venga modificato in modo indivisibile, perché il filesystem non offre questa proprietà. E non dichiara di poter sempre concludere o riportare indietro, perché volume scomparso, permessi revocati, spazio esaurito o Cestino svuotato lo rendono talvolta impossibile. Dichiara di **riconoscere sempre lo stato raggiunto**, di tentare ripresa o compensazione, e di **nominare esplicitamente ciò che richiede intervento umano**.
- **NFR-A4** L'app non modifica mai un file che l'utente non ha esplicitamente incluso in un'operazione. In particolare, registrare un giudizio non comporta **in nessun caso** la riscrittura del file immagine.
- **NFR-A5** Un file corrotto, troncato o di formato inatteso non compromette il caricamento della cartella né alcuna operazione sugli altri file. Lo stesso vale per un sidecar malformato: viene segnalato e ignorato, mai riscritto alla cieca.
- **NFR-A6** La scrittura di un sidecar è atomica sul singolo file: un arresto anomalo non può produrre un sidecar parziale né perdere il giudizio precedente.
- **NFR-A7** Nessuna perdita silenziosa di un giudizio: una scrittura fallita lascia il giudizio nello stato durevole, è visibile all'utente ed è riprovabile.
- **NFR-A8** Nessun conflitto risolto in silenzio, **nemmeno quando l'altra applicazione non si è coordinata**: la scrittura del sidecar è verificata dopo la sostituzione, e un'interferenza rilevata produce un conflitto dichiarato con possibilità di recupero del valore precedente.
- **NFR-A9** La correttezza della vista non dipende dalla completezza delle notifiche del filesystem: in ogni condizione — eventi persi, identificatori riavvolti, volume rimontato — una riconciliazione riporta il catalogo in accordo con il disco, e quando non può essere completata l'app lo dichiara.
- **NFR-A10 Autorità direzionale tra le sedi del dato.** Stato durevole e sidecar prevalgono sulla cache derivata, che può restare indietro ed essere riallineata. L'ordine di scrittura è dichiarato — stato durevole, poi sidecar, poi cache — e le righe non allineate sono riconciliate al riavvio. La cache non è mai la fonte in caso di divergenza.
- **NFR-A11 Durabilità dello stato locale.** Lo stato durevole usa impostazioni di journaling e sincronizzazione scelte per la sicurezza della scrittura e non per la velocità; è sottoposto a controllo di integrità all'avvio; dispone di un percorso di recupero da corruzione che ricostruisce il ricostruibile, mette in quarantena il resto e lo dichiara; ha una retention limitata e dichiarata della cronologia; e ha un comportamento definito su disco pieno e su migrazione fallita, che in nessun caso è ripartire in silenzio da uno stato vuoto.
- **NFR-A12** Il comando di svuotamento della cache non può in nessun caso rimuovere il registro delle operazioni, un lotto non completato o un giudizio non ancora scritto nel suo sidecar. La proprietà è garantita dalla separazione fisica degli archivi ed è coperta da test dedicati.
- **NFR-A13** Nessun punteggio in cache è confrontato con uno calcolato da una versione diversa degli strumenti o delle soglie: al cambio di versione i valori sono considerati non validi e ricalcolati o segnalati come tali.

### Sicurezza

- **NFR-S1 Nessuna rete a tempo di esecuzione.** L'app non invia immagini, metadati, dati derivati né telemetria a nessun servizio remoto. L'unica connessione ammessa è l'eventuale download iniziale del modello estetico, se non incluso nel bundle: esplicita, verso un'origine dichiarata, verificata per integrità e rinunciabile. Sono escluse anche le materializzazioni implicite di file remoti causate dalla sola visualizzazione (FR-016).
- **NFR-S2 Nessun account, nessuna credenziale, nessun dato personale raccolto.** Non esiste autenticazione perché non esiste nulla da autenticare.
- **NFR-S3 Distribuzione firmata.** Binario firmato con hardened runtime e notarizzato da Apple; nessuna disattivazione di Gatekeeper richiesta all'utente. Il canale `.dmg` notarizzato è già distribuzione a terzi utilizzabile; la sandbox è il presupposto del Mac App Store, non della distribuzione.
- **NFR-S4 Permesso minimo necessario.** L'app opera senza sandbox ma **non richiede l'Accesso completo al disco**: si affida al consenso contestuale per le categorie protette e all'accesso concesso aprendo o trascinando una cartella. Il permesso più ampio è un'opzione, mai un prerequisito.
- **NFR-S5 Punto unico di scrittura — confine di codice, non di sicurezza.** Tutte le scritture, gli spostamenti e le eliminazioni passano da un unico livello, coperto da test dedicati, che è anche il punto d'innesto della futura sandbox. Questo livello **non riduce i privilegi del processo** e non va inteso come contenimento: il perimetro di sicurezza reale è trattato in NFR-S6.
- **NFR-S6 I file sono dati non fidati.** L'app interpreta immagini che l'utente non ha prodotto, in un processo non in sandbox con accesso ai suoi file. Il rischio è **dichiarato e accettato** per l'MVP (ADR-016) con queste condizioni: nessun percorso interpreta il contenuto di un file come codice o esegue contenuto incorporato; ogni errore di decodifica è contenuto al singolo file e segnalato; l'integrazione continua include un corpus di file troncati, corrotti e con intestazioni incoerenti; hardened runtime e validazione delle librerie sono attivi. L'isolamento di decodifica e analisi in un processo separato è previsto come evoluzione, con l'innesto già collocato nell'architettura.
- **NFR-S7 Dati sensibili nei metadati.** Le coordinate GPS sono trattate come informazione sensibile: mostrate su richiesta, mai incluse in nomi generati automaticamente, mai copiate in un sidecar, e rimovibili in esportazione (fase di crescita).
- **NFR-S8 Superficie delle dipendenze ridotta al minimo.** L'unica dipendenza esterna a tempo di esecuzione è GRDB.swift; tutto il resto è framework di sistema, e il formato dei sidecar è XML gestito senza librerie di terze parti. Ogni nuova dipendenza richiede una decisione architetturale registrata.
- **NFR-S9 Provenienza del modello.** Il modello estetico open source è versionato, la sua licenza è verificata come compatibile con la distribuzione, e la sua origine e conversione sono documentate nel repository.

### Integrazioni

Tutte le integrazioni sono con il sistema operativo o con formati standard aperti; non esiste alcuna integrazione con servizi di terze parti.

- **NFR-I1 QuickLook Thumbnailing** — generazione delle anteprime per i formati supportati dal sistema, con riuso della cache di sistema.
- **NFR-I2 ImageIO** — lettura di metadati EXIF/IPTC/GPS/TIFF, decodifica sempre ridimensionata, scrittura in fase di salvataggio con preservazione dei metadati.
- **NFR-I3 Vision** — feature print per la similarità visiva, rilevamento volti, qualità di cattura del volto, **landmark** oculari. Lo stato aperto/chiuso degli occhi **non** è fornito dal sistema: è un'euristica dell'app, dichiarata e calibrata (ADR-014).
- **NFR-I4 Core ML** — esecuzione locale del modello estetico, su richiesta e su insiemi già ridotti.
- **NFR-I5 Core Image e Metal** — trasformazioni geometriche, istogrammi, misure di nitidezza, con accelerazione GPU.
- **NFR-I6 File System Events** — rilevamento delle modifiche alla cartella aperta, con eventi a granularità di file, identificatore d'evento persistito e legato al volume, e gestione esplicita di eventi persi, identificatori non più validi e volumi smontati. Il contratto può non essere uniforme fra classi di volume: dove non lo è, l'app adotta un meccanismo diverso e lo dichiara.
- **NFR-I7 Coordinamento file di sistema** — coordinamento degli accessi concorrenti al sidecar. È **cooperativo**: vincola solo le applicazioni che vi partecipano, quindi va accompagnato da verifica successiva alla scrittura e recupero esplicito. Non crea una transazione.
- **NFR-I8 Cestino di macOS** — unica via di eliminazione. Il sistema sposta l'elemento e riferisce dove è finito; il ripristino resta nelle mani dell'utente e del sistema e non è promesso dall'app.
- **NFR-I9 XMP (schema Basic)** — formato standard aperto per rating e rappresentazione dello scarto. L'interoperabilità con Bridge, Lightroom, darktable e digiKam è un **obiettivo verificato da test di round-trip reali** (cancello n°3), non una proprietà che il formato garantisca.
- **NFR-I10 Chiavi di risorsa di Foundation** — identità e validità dei file dalle primitive di sistema; la combinazione adottata è l'esito del cancello n°2.
- **NFR-I11 XPC** — non usato nell'MVP; registrato come meccanismo previsto per l'isolamento futuro di decodifica e analisi (ADR-016), così che introdurlo non richieda di rivedere i confini dei componenti.
- **NFR-I12 Servizi Finder** — rivela nel Finder, apri con, foglio di condivisione di sistema.
- **NFR-I13 Accessibilità di sistema** — VoiceOver, *Riduci movimento*, *Aumenta contrasto*, dimensione del testo.
- **NFR-I14 Nessuna integrazione con la libreria Foto di macOS** nell'MVP: scelta esplicita coerente con "la cartella è la fonte di verità".

---

## Next Steps

<!-- archetipo:prd section=next_steps required=true -->

1. **Tappa 0 — Cancelli tecnici** - Esegui i quattro spike e registrane l'esito: possono modificare ADR-007, 009, 011, 012 e 013 prima che venga scritta una riga di applicazione. Le revisioni dell'architettura sulla carta si chiudono qui: le domande rimaste si chiudono misurando
2. **Backlog** - Esegui `/archetipo-spec` per trasformare questo PRD in un backlog, con le tappe di consegna come struttura portante
3. **Design** - Esegui `/archetipo-design` per i mockup dell'interfaccia (quando applicabile)
4. **Validazione** - Rivedi con gli stakeholder e metti alla prova gli assunti più rischiosi

---

_PRD generato tramite ARchetipo Product Inception - 2026-08-24_
_Revisione architetturale 1.1 - 2026-08-25_
_Revisione architetturale 1.2 - 2026-08-26_
_Revisione architetturale 1.3 - 2026-08-26_
_Sessione condotta da: alessandro.giardina@intre.it con il team ARchetipo_
