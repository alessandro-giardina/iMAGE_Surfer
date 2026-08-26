# iMAGE Surfer - Product Requirements Document

**Autore:** ARchetipo
**Data:** 2026-08-26
**Versione:** 1.2

> **Revisione 1.2** — Seconda revisione architetturale esterna. Il rilievo di fondo era che il documento confondeva *intenzione*, *meccanismo plausibile* e *garanzia assoluta*: la 1.1 prometteva atomicità multi-file, conservazione dei giudizi «sempre», e un indice «integralmente ricostruibile» che nel frattempo era diventato l'unica sede del journal. Questa revisione **abbassa le promesse al livello che l'architettura può reggere** e alza il livello di specificazione dove serviva. Modifiche sostanziali: separazione fisica tra cache eliminabile e stato durevole (ADR-003); operazioni massive come macchina a stati **recuperabile**, non atomica (ADR-007); code separate sotto budget comune con banda di ritenzione (ADR-009); identità come matrice esplicita di casi supportati e best-effort (ADR-011); contratto FSEvents esteso a volumi, ID riavvolti e tempo massimo di riconciliazione (ADR-012); scrittura XMP con coordinamento tra processi e stato di sincronizzazione esplicito (ADR-013); punteggi di qualità come euristica dichiarata e versionata (ADR-014); quattro cancelli tecnici e consegna a tappe prima del full build (ADR-015). Lo scope dell'MVP non è stato ridotto.

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
| Advocacy | Lo mostra a un amico fotografo e gli manda il `.dmg` | "Questo risolve un problema che abbiamo tutti e nessuno risolve" | Soddisfazione | Prevedere un percorso di distribuzione a terzi (sandbox e firma) come evoluzione |

---

### Persona 2: Adalgisa - la selezionatrice sotto scadenza

**Ruolo:** Content/social manager in una PMI; riceve materiale fotografico da fotografi esterni e colleghi
**Età:** 25-40 | **Background:** Ogni settimana le arriva una cartella condivisa con 200-500 immagini di un evento o di un prodotto. Deve consegnare pochi scatti selezionati, nominati secondo la convenzione aziendale e ordinati in sottocartelle per canale.

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

> Scoperte chiave e direzioni alternative esplorate durante la sessione di inception e durante le due revisioni architetturali successive.

### Assunti Messi in Discussione

- **"Le cinque frustrazioni sono cinque funzioni da aggiungere."** Falso: sono un unico problema. Il Finder è un file manager che tollera le immagini. La conseguenza progettuale è che il cuore dell'app non è la griglia di anteprime, ma il **ciclo di triage** guarda → giudica → agisci → prossima, interamente a tastiera. Ogni funzione va valutata su quanto accorcia quel ciclo.
- **"Esiste un 'migliore' oggettivo che un modello può calcolare."** In gran parte falso, e il prodotto ne dipende. Su una raffica di scatti quasi identici "migliore" significa quasi sempre grandezze misurabili (a fuoco, non mosso, occhi aperti, esposizione sana) e solo di rado "più bello". Da qui la regola non negoziabile: **l'AI argomenta, non decreta**, e non cancella mai nulla da sola.
- **"L'AI è la funzione che vende, quindi va messa al centro."** Vera solo a metà. Il differenziatore commerciale è l'AI; il differenziatore d'uso quotidiano è la **latenza**. Conseguenza architetturale: analisi AI **solo su richiesta, solo su una selezione**, mai in scansione di cartella.
- **"Le frecce sono un dettaglio di comodità."** Falso: sono l'intero contratto di interazione. Se le frecce spostano la selezione, allora *tutto* il resto deve essere raggiungibile senza lasciare la tastiera. Questo vincola la mappa dei tasti a essere completa dal primo giorno.
- **"Bisogna scegliere un solo criterio di selezione."** Superato dal confronto: i criteri sono in **cascata ordinata** — prima si raggruppano gli scatti quasi identici, poi si valuta il soggetto, infine la qualità tecnica fa da spareggio.
- **"L'indice locale è una cache buttabile."** Vero solo per metà. È cache tutto ciò che è **ricalcolabile** dai file; non lo è ciò che l'utente ha **creato**. Conseguenza: i giudizi hanno un contratto di durabilità proprio (ADR-003, ADR-013).
- **"Basta separare i giudizi dalla cache."** Insufficiente, e la revisione 1.1 lo aveva mancato: nello stesso archivio erano finiti anche il **journal delle operazioni** e le **scritture sidecar non riuscite**, che non sono ricalcolabili da nulla. Con un pulsante "svuota indice" ancora in interfaccia, quel pulsante distruggeva la cronologia di annullamento e l'unica copia di alcuni giudizi. Non è un rischio teorico: è la stessa classe di difetto già corretta una volta, rientrata da un'altra porta. Conseguenza: separazione **fisica** tra cache eliminabile e stato durevole (ADR-003).
- **"Immagine e sidecar sono un'unità indivisibile."** Falso, e non per approssimazione: **non esiste** una transazione che sposti due file — tantomeno ottocento — come un solo commit. Un arresto può sempre cadere tra un passo e l'altro. Il journal non rende un lotto atomico: se progettato bene lo rende **recuperabile**, che è una proprietà diversa e più debole. Conseguenza: ADR-007 riscritto come macchina a stati con log di intenti, e la parola "indivisibile" eliminata dal documento.
- **"L'anteprima obbligatoria protegge l'utente."** Vera solo se le precondizioni vengono **ricontrollate dopo il dry-run**. Tra l'anteprima e il clic di conferma il filesystem può cambiare: senza quel ricontrollo, lo strumento che avevamo introdotto per generare fiducia diventa la fonte del danno.
- **"Il Cestino garantisce il ripristino."** Falso. Il sistema sposta l'elemento nel Cestino e riferisce dove è finito; non promette che vi resti né che sia sempre ripristinabile — l'utente può svuotarlo. Il Cestino è reversibile *per l'utente*, non garantito *dal sistema*.
- **"I giudizi sopravvivono agli spostamenti fatti fuori dall'app."** Promessa non mantenibile. Se nel Finder l'utente sposta solo `foto.jpg`, il Finder non sa che `foto.xmp` è collegato e lo lascia indietro; e l'app osserva solo la cartella aperta, quindi non sa dove l'immagine sia finita. Conseguenza: al posto della promessa, una **matrice esplicita dei casi** con tre livelli — supportato, recupero best-effort, non supportato.
- **"L'hash è già calcolato, quindi l'identità di riserva è gratuita."** Contraddizione interna al documento, non un'approssimazione: l'identità di riserva assumeva un hash disponibile per ogni file, mentre il rilevamento dei duplicati calcola lo SHA-256 completo **solo su collisione**. Calcolarlo per tutti significa leggere integralmente 50.000 file, cioè violare i vincoli di latenza che sono il rischio primario. E anche fosse gratuito non sarebbe un'identità: due duplicati esatti condividono lo stesso hash, e una modifica al contenuto lo cambia. Conseguenza: l'hash resta **recupero best-effort su materiale già indicizzato**, mai identità primaria.
- **"`volume + inode` è l'identità del file."** Formulazione artigianale al posto delle primitive che il sistema espone. Le candidate hanno proprietà diverse e nessuna copre tutto: l'identificatore di risorsa non è persistente tra un riavvio e l'altro; l'identificatore di documento è pensato per sopravvivere agli spostamenti sullo stesso volume e ai salvataggi atomici ma non alle copie; i bookmark sono la forma persistente. Quale combinazione regga davvero **non si decide in un PRD**: è uno dei cancelli tecnici (ADR-015).
- **"La riconciliazione con finestra di quiete risolve gli eventi del filesystem."** Risolve il caso facile. Restavano fuori: identificatore d'evento legato al volume, volumi smontati o ripristinati, identificatori eliminati o riavvolti, cambio della radice osservata, e il comportamento su volumi di rete e cartelle sincronizzate, dove i file possono essere segnaposto non materializzati. E soprattutto: **una raffica continua non raggiunge mai la finestra di quiete**, quindi uno scarico di schede lungo rimanda la riconciliazione a tempo indefinito. Serve un tempo massimo, non solo un debounce.
- **"Rileggo il sidecar e riscrivo invariato ciò che non conosco."** Non protegge da un'altra applicazione che scrive tra la nostra lettura e la nostra sostituzione. Serve controllo ottimistico sulla versione osservata, coordinamento tra processi, e un conflitto **esplicito** invece di una risoluzione silenziosa.
- **"Vince la fonte modificata più di recente."** Non è una politica, è una speranza. Al suo posto uno **stato di sincronizzazione esplicito** per immagine — pulito, scrittura in attesa, scrittura fallita, conflitto esterno — con revisione, provenienza e ultima versione XMP osservata.
- **"XMP standard, quindi interoperabile."** Non segue. Restano da decidere la convenzione del nome, la collisione tra due immagini con la stessa radice e formati diversi, e come si rappresenta "da scartare" — dove `xmp:Label` ha semantica non uniforme tra gli strumenti e il candidato più difendibile è la convenzione `xmp:Rating = -1`. Finché non esiste un round-trip provato su strumenti reali, "interoperabile" è un'ipotesi.
- **"Vision dice se gli occhi sono aperti."** Falso, ed è un errore di categoria: Vision fornisce i **landmark** oculari, non un classificatore documentato dello stato aperto/chiuso. Quella conclusione la produciamo noi, con un'euristica da calibrare su occhiali, profilo, occlusioni e volti piccoli.
- **"I criteri della cascata sono indipendenti."** Falso, e questo tocca il differenziatore. Il punteggio di qualità di cattura del volto è **olistico**: incorpora illuminazione, nitidezza, posa, centratura. Metterlo allo stadio 2 e poi mettere nitidezza ed esposizione allo stadio 3 conta due volte le stesse grandezze — e mostrare all'utente "volto: buono" accanto a "nitidezza: alta" come due ragioni distinte **non è una spiegazione, è una ripetizione travestita da conferma**. Se la spiegabilità è il differenziatore, la sovrapposizione va dichiarata.
- **"Uno scheduler unico protegge le risorse."** Un punto unico di ammissione per I/O, decodifica, visione artificiale e database diventa un componente onnisciente e un collo di bottiglia. E le dimensioni in pixel non stimano la memoria di un modello Core ML, di una texture GPU, di un HEIC multipagina o di una risorsa QuickLook. Conseguenza: **code separate** sotto una politica di budget comune, con costi **misurati** e non dedotti.
- **"Cancellare subito il lavoro delle celle uscite dallo schermo è una virtù."** Lo era finché non si guarda uno scroll reale: due righe avanti e due indietro ributtano via il lavoro appena fatto. Serve una **banda di ritenzione attorno alla viewport con isteresi** — e quella banda è memoria occupata di proposito, quindi la sua ampiezza è un parametro del budget e non una costante dell'interfaccia.
- **"Il costo dell'MVP allargato è dichiarato, quindi gestito."** Non segue. Dichiarare il costo affronta il rischio di **sforzo**, non quello di **integrazione**: browser performante, sistema di metadati, motore di operazioni recuperabili, interoperabilità XMP, rilevatore di duplicati, pipeline ML, editor e accessibilità devono funzionare *insieme*, ciascuno con le sue modalità di guasto. Conseguenza: quattro cancelli tecnici e consegna a tappe (ADR-015).

### Nuove Direzioni Scoperte

- **Anti-problem ("come rendiamo questa app inutilizzabile?").** Le risposte hanno prodotto i vincoli non funzionali più utili del documento. Le due revisioni successive ne hanno aggiunti quattro: bruciare CPU reagendo a ogni evento del filesystem; crescere in memoria fino all'arresto silenzioso; **promettere garanzie che il filesystem non può mantenere**, che è il modo più rapido di perdere la fiducia una volta sola e per sempre; e **buttare via il lavoro appena fatto** a ogni piccolo movimento di scroll.
- **"E se togliessimo l'AI?" (what if).** L'app resterebbe utile: filtro dei soli file immagine, anteprime grandi, navigazione a frecce e pannello metadati risolvono già quattro frustrazioni su cinque. Questo dà l'ordine di implementazione: **il triage a tastiera deve stare in piedi da solo**, e la parte AI si innesta sopra un'app già funzionante. È diventato la struttura delle tappe di consegna.
- **Audience flip (dal proprietario del Mac al team).** Preset condivisibili e distribuzione a terzi sono rinviati alla crescita, ma l'architettura non deve precluderli: le regole vanno modellate come dati serializzabili, non come codice.
- **Il sidecar non è una difesa, è un'interfaccia.** È la prima funzione che fa **parlare iMAGE Surfer la lingua degli altri strumenti**. Ma proprio perché è un'interfaccia, la sua correttezza non si dimostra leggendo una specifica: si dimostra con un round-trip su strumenti reali. È diventato uno dei quattro cancelli.
- **La matrice dei casi come funzione di prodotto.** Nata per sostituire una promessa insostenibile, l'elenco esplicito di cosa l'app sa seguire e cosa no si è rivelato più utile della promessa stessa: Guidalberto riorganizza le cartelle nel Finder e vuole sapere *in anticipo* dove sta il confine. Una garanzia falsa lo perde una volta sola; un limite dichiarato lo mette in condizione di lavorarci intorno.
- **Il journal come funzione, non come dettaglio tecnico.** Registrare ogni lotto rende possibile un annullamento che sopravvive alla chiusura dell'app. Con la riscrittura di ADR-007 diventa anche la base della **ripresa dopo un arresto**: lo stesso registro serve a due scopi, ed è la ragione per cui vive nello stato durevole e non nella cache.
- **Il pannello metadati come acceleratore di selezione.** ISO alto e tempo lungo *predicono* rumore e mosso: gli stessi metadati che l'utente legge alimentano l'ordinamento dei candidati.
- **Il versionamento semantico dei punteggi.** Registrare accanto a ogni punteggio la revisione di Vision, la versione del modello, il preprocessing e le soglie costa pochissimo e impedisce che il primo aggiornamento di sistema renda i punteggi in cache silenziosamente incomparabili. Senza, la cache non è più veloce: è sbagliata.
- **I cancelli tecnici come parte del prodotto, non del piano.** Quattro spike che possono invalidare una decisione architetturale non sono attività di progetto: sono la differenza tra un'architettura proposta e un'architettura verificata. Per questo stanno nel PRD e non in un piano a parte.
- **Il momento del permesso come momento di progetto.** Il consenso al filesystem è l'unico istante in cui il sistema si mette tra l'utente e le sue foto. Chiesto **dopo il gesto che lo motiva** è una conseguenza ovvia; chiesto prima è un ostacolo.

### Assunti da Validare

- **Identità del file.** Quale combinazione tra identificatore di risorsa, identificatore di documento, UUID del volume e bookmark regga sui casi reali — riavvio, rimontaggio, salvataggio atomico di un'altra app, copia, volume esterno — è **la domanda aperta più importante del documento**, perché da essa dipende la matrice dei casi supportati. Oggetto del cancello tecnico n°2.
- **Convenzione di nome del sidecar.** `foto.xmp` o `foto.jpg.xmp`? La prima è più diffusa tra gli strumenti fotografici, la seconda risolve la collisione tra `foto.jpg` e `foto.heic` nella stessa cartella. *Da decidere sul round-trip reale, non a tavolino.*
- **Rappresentazione di "da scartare".** Candidato: la convenzione `xmp:Rating = -1`, più uniformemente interpretata di `xmp:Label`. *Da verificare su Bridge, Lightroom, darktable e digiKam, insieme al comportamento sui campi che non conosciamo.*
- **Politica di conflitto sul sidecar.** Lo stato esplicito sostituisce la regola sulla data di modifica, ma resta da decidere **cosa mostra l'interfaccia** su un conflitto esterno: risoluzione proposta con conferma, oppure due valori affiancati. *Da validare sull'uso reale.*
- **Ampiezza della finestra di quiete e tempo massimo di riconciliazione.** Due parametri, non uno. Troppo corta la prima e si reagisce a scritture in corso; troppo lungo il secondo e durante uno scarico di schede la vista resta indietro.
- **Comportamento su volumi di rete e cartelle sincronizzate.** Segnaposto non materializzati, latenza di rete, eventi assenti o diversi. *Assunto per l'MVP: si mostra lo stato senza scaricare implicitamente. Da verificare nel cancello n°2.*
- **Costo in memoria per tipo di lavoro.** Le dimensioni in pixel non bastano. Servono misure reali per decodifica, visione artificiale, modello Core ML, anteprime di sistema e HEIC multipagina, e da quelle si deriva il budget. Oggetto del cancello n°1.
- **Ampiezza della banda di ritenzione.** Compromesso diretto tra thrashing e memoria, da calibrare insieme al budget e non separatamente.
- **Euristica occhi aperti/chiusi.** Costruita sui landmark, va calibrata su occhiali, profilo, occlusioni e volti piccoli, e va dichiarato il suo tasso di errore invece di presentarla come dato certo. *Se non raggiunge un'affidabilità accettabile, va mostrata come indizio e non come criterio.*
- **Sovrapposizione tra qualità del volto e qualità tecnica.** Da misurare su materiale reale: quanto il punteggio olistico di cattura del volto correla con nitidezza ed esposizione calcolate a parte. *Il risultato decide se quel punteggio resta un criterio o diventa solo un filtro di ammissione allo stadio successivo.*
- **Utilità reale del punteggio estetico.** Incluso nell'MVP su scelta esplicita. *Se dopo l'uso reale non sposta le decisioni, va declassato a criterio opzionale disattivabile.*
- **Peso e provenienza del modello estetico.** *Bundle unico più grande, oppure download al primo utilizzo? La seconda strada introduce l'unica connessione di rete dell'app.*
- **RAW rinviato alla crescita.** *Se in pratica gli scatti importanti sono RAW, la priorità va rivista subito: coppia RAW+JPEG e sidecar condiviso non sono un dettaglio da aggiungere dopo senza costi.*
- **Ricorsività delle operazioni massive.** Assunto per l'MVP: si agisce sulla cartella corrente. *Da confermare: la ricorsione moltiplica i modi in cui un'operazione massiva può fare danni.*
- **Nessuna integrazione con la libreria Foto di macOS.** *Da confermare.*
- **Numero di "migliori" da tenere.** Modellato come parametro (default 3), non come costante.
- **Tenuta dello scope.** Due revisioni indipendenti hanno segnalato che l'insieme è più vicino a una v1 professionale che a un MVP. La risposta scelta è la consegna a tappe con cancelli tecnici, senza rimuovere funzioni. *Da rivedere alla fine del cancello n°1: se le misure di prestazione e memoria non reggono, Area 12 — Editing di base e il punteggio estetico sono i due candidati dichiarati al rinvio.*

### Rischi Principali

- **Rischio di esecuzione — latenza percepita.** È il rischio primario. Se aprire una cartella da 3.000 immagini non è immediato, l'app perde contro il Finder a prescindere dal resto. Mitigazione: anteprime dal servizio di sistema con cache su disco, decodifica solo di ciò che serve, banda di ritenzione con isteresi, indice persistente. Verificato dal cancello n°1.
- **Rischio di adozione — sfiducia nell'AI.** Una proposta non spiegata viene disattivata dopo pochi utilizzi. Mitigazione: motivazioni sempre visibili **e realmente distinte**, sovrapposizioni dichiarate, soglie regolabili, nessuna azione distruttiva automatica.
- **Rischio di perdita dati sulle operazioni massive.** Rinominare o spostare centinaia di file è la funzione più utile e la più pericolosa. Mitigazione a quattro livelli: anteprima obbligatoria, **ricontrollo delle precondizioni prima dell'esecuzione**, log di intenti con passi idempotenti che permette ripresa o compensazione, eliminazioni sempre nel Cestino. Verificato dal cancello n°4.
- **Rischio di perdita del lavoro di giudizio.** Si materializza quando l'utente riorganizza le cartelle fuori dall'app, cambia Mac, o svuota la cache. Mitigazione: sidecar accanto all'immagine, stato durevole separato dalla cache eliminabile, e **matrice dei casi dichiarata** al posto di una promessa generale.
- **Rischio di fiducia — promettere garanzie non mantenibili.** Distinto da tutti i precedenti e più pericoloso: un limite dichiarato in anticipo si aggira, una garanzia smentita una volta sola distrugge la credibilità di tutte le altre. Mitigazione: le parole "sempre", "garantito" e "indivisibile" non compaiono nel documento dove il sistema può offrire soltanto recupero o best-effort, e ogni contratto è espresso al livello che l'architettura regge.
- **Rischio tecnico — coerenza della cache.** Un indice disallineato produce anteprime sbagliate o file fantasma. Mitigazione: identità e validità come chiavi distinte, riconciliazione al posto della fiducia negli eventi, cache sempre ricostruibile.
- **Rischio tecnico — tempesta di eventi del filesystem.** Mitigazione: finestra di quiete **e** tempo massimo di riconciliazione, coalescenza per ambito, esclusione delle scritture dell'app stessa, gestione esplicita di identificatori persi o riavvolti e di volumi smontati. Verificato dal cancello n°2.
- **Rischio tecnico — esaurimento silenzioso della memoria.** Mitigazione: decodifica sempre ridimensionata, blocchi di rilascio per singolo elemento, code separate sotto budget misurato, reazione alla pressione di memoria, e un test di lunga durata che fallisce la build sulla crescita monotona. Verificato dal cancello n°1.
- **Rischio di interoperabilità — sidecar che gli altri strumenti non leggono.** Il sidecar è venduto come portabilità: se Bridge o Lightroom non vedono le stelle, non è una funzione degradata, è una funzione assente. Mitigazione: convenzioni decise sul round-trip reale, campi sconosciuti conservati, coordinamento tra processi e conflitti espliciti. Verificato dal cancello n°3.
- **Rischio di adozione — attrito dei permessi al primo avvio.** Mitigazione: nessun permesso prima del gesto che lo motiva, nessun Accesso completo al disco come prerequisito, stato di rifiuto spiegato e recuperabile.
- **Rischio di integrazione — troppi sottosistemi che si incontrano lo stesso giorno.** Il rilievo di entrambe le revisioni. Non è un rischio di sforzo e non si risolve accettando più tempo: nasce dal fatto che otto sottosistemi con modalità di guasto diverse verrebbero integrati per la prima volta insieme. Mitigazione: quattro cancelli tecnici prima del full build e consegna a tappe, ognuna utilizzabile da sola.
- **Rischio di scope — l'editing.** L'MVP contiene solo trasformazioni geometriche. È il primo candidato dichiarato al rinvio se il cancello n°1 mostra che le stime non reggono.
- **Rischio operativo — assenza di sandbox.** Limita la distribuzione a terzi. Accettato per l'MVP; ogni accesso passa da un livello unico, che è il punto d'innesto dei bookmark con ambito di sicurezza.

---

## Product Scope

<!-- archetipo:prd section=product_scope required=true -->

### MVP - Minimum Viable Product

Il criterio di taglio dell'MVP: **risolvere tutte e cinque le frustrazioni dichiarate, più le tre capacità richieste (a, b, c), sulla scala reale di 10.000-50.000 immagini, senza mai mettere a rischio i file né il lavoro di giudizio dell'utente, e senza promettere garanzie che il sistema non può mantenere**. Tutto ciò che non serve a questo è fuori.

Lo scope è ampio e questo è riconosciuto: due revisioni architetturali indipendenti hanno osservato che l'insieme è più vicino a una prima versione professionale che a un minimo prodotto. La risposta non è ridurre le funzioni ma **verificarne i presupposti prima di costruirle e consegnarle in tappe utilizzabili**, come descritto in *Percorso di consegna*.

**1. Apertura e navigazione delle cartelle**
- Apertura tramite trascinamento, dialogo di sistema, cartelle recenti o preferiti nella barra laterale.
- **Solo le immagini sono visibili** (frustrazione 1); contatore del contenuto non-immagine, che distingue i file collegati dal resto.
- Ordinamento per nome, data di scatto, data di modifica, dimensione, rating.
- Nessun permesso richiesto prima del gesto che lo motiva.

**2. Sincronizzazione con il filesystem**
- Aggiornamento automatico quando la cartella cambia sotto l'app, anche per opera di altre applicazioni.
- Gli eventi del sistema sono un suggerimento: la verità è una riconciliazione per differenza.
- Riconciliazione garantita entro un tempo massimo anche sotto raffica continua, e nessun consumo di risorse a cartella ferma.
- Le modifiche avvenute mentre l'app era chiusa sono rilevate alla riapertura; volumi smontati, rimontati o con cronologia degli eventi non più disponibile sono gestiti esplicitamente.
- Su volumi di rete e cartelle sincronizzate, i file non ancora materializzati sono mostrati come tali e mai scaricati implicitamente.

**3. Visualizzazione a griglia e anteprima grande**
- Griglia con cella regolabile fino a molto grande (frustrazione 2), fluida su migliaia di elementi.
- Anteprima grande a pannello e a schermo intero, con zoom fino a 1:1 e panoramica.
- **Navigazione integralmente a frecce** (frustrazione 3); selezione multipla da tastiera.

**4. Metadati sempre a portata d'occhio**
- Pannello permanente e commutabile con un tasto: dati file, dimensioni, EXIF, IPTC, GPS, spazio colore (frustrazione 4).
- Segue la selezione senza latenza percepibile; per selezioni multiple mostra i valori comuni.

**5. Giudizio, marcatura e loro durabilità**
- Rating 1-5 stelle e marcatura "da scartare" da tastiera; filtri per rating, marcatura, formato, intervallo di date.
- **I giudizi sono scritti in un sidecar XMP accanto all'immagine**, in formato standard, oltre a essere tenuti nello stato locale. L'immagine originale non viene mai aperta in scrittura.
- **Stato di sincronizzazione esplicito** per ogni immagine: pulito, scrittura in attesa, scrittura fallita, conflitto esterno. Nessun conflitto risolto in silenzio.
- **Matrice dichiarata** dei casi in cui l'associazione con l'immagine regge, viene recuperata a tentativo, o non è recuperabile.

**6. Operazioni su file, singole e massive**
- Spostamento, copia, rinomina di singole immagini e di selezioni; il sidecar è incluso nell'operazione.
- Eliminazione **sempre tramite il Cestino di macOS**, mai con cancellazione diretta.
- **Rinomina massiva guidata da pattern** (capacità a), con anteprima obbligatoria `da → a`, ricontrollo delle precondizioni prima dell'esecuzione, politica esplicita per collisioni e metadati mancanti.
- **Creazione massiva di sottocartelle e smistamento per regole** (capacità b), con lo stesso contratto.
- Ogni lotto è **recuperabile**: registrato prima dell'esecuzione, eseguito in passi idempotenti, ripreso o compensato dopo un arresto.

**7. Duplicati**
- Rilevamento dei **duplicati esatti** per contenuto, con pannello di risoluzione che propone quale copia tenere.
- Rilevamento dei **gruppi di quasi-duplicati** con soglia regolabile.

**8. Selezione assistita — "tieni le migliori N"** (capacità c, frustrazione 5)
Pipeline in cascata: raggruppamento per similarità visiva e temporale → analisi del soggetto → qualità tecnica misurabile → punteggio estetico come spareggio finale.
- Proposta di N immagini (default 3, regolabile) **con le motivazioni sempre visibili**, e con le sovrapposizioni tra criteri dichiarate invece che presentate come conferme indipendenti.
- Nessuna azione distruttiva automatica; esecuzione **solo su richiesta e solo su una selezione**.
- Ogni punteggio memorizzato porta con sé la versione degli strumenti e delle soglie che lo hanno prodotto.

**9. Editing di base**
- Rotazione di 90°, capovolgimento orizzontale e verticale, ritaglio con proporzioni libere e predefinite.
- Salvataggio come copia oppure sovrascrittura, con scelta esplicita e conservazione dei metadati.

**10. Fondamenta trasversali**
- **Due archivi locali distinti**: una cache eliminabile di dati ricalcolabili, e uno stato durevole che contiene il registro delle operazioni, i lotti incompleti e i giudizi non ancora scritti nei sidecar.
- Un unico livello di accesso al filesystem: l'unico punto del codice che può scrivere, spostare o eliminare.
- **Code separate** per ingresso/uscita, decodifica, visione artificiale e archivio, coordinate da un budget di memoria comune misurato, con banda di ritenzione attorno alla parte visibile.
- Mappa dei tasti completa e visibile in un pannello di aiuto.
- Accessibilità: etichette VoiceOver, rispetto di *Riduci movimento* e *Aumenta contrasto*, operabilità totale da tastiera.

### Percorso di consegna

Lo scope non è ridotto, ma non viene nemmeno costruito e integrato tutto insieme. La sequenza è vincolante.

**Tappa 0 — Cancelli tecnici.** Quattro verifiche che precedono il full build. Ognuna può invalidare una decisione architetturale, e ognuna produce un esito scritto che aggiorna gli ADR corrispondenti. Non sono attività preparatorie: sono la differenza tra un'architettura proposta e un'architettura verificata.

| # | Cancello | Domanda a cui risponde | ADR che può invalidare |
|---|---|---|---|
| 1 | **Prestazioni e memoria su 50.000 file** su dataset e hardware dichiarati | Il vincolo di latenza regge? Qual è il costo reale in memoria per tipo di lavoro? Quanto deve essere ampia la banda di ritenzione? | ADR-009, e con esso i vincoli NFR-P1, NFR-P9, NFR-P10 |
| 2 | **Matrice degli eventi del filesystem** su APFS, volume esterno, cartella sincronizzata e volume di rete | Quali primitive di identità reggono davvero? Come si comportano gli eventi quando un volume viene smontato, o quando la cronologia non è più disponibile? | ADR-011, ADR-012, e la matrice dei casi di FR-049 |
| 3 | **Round-trip XMP** con Bridge, Lightroom, darktable e digiKam, inclusa la scrittura concorrente | Il sidecar è davvero interoperabile? Quale convenzione di nome? Come si rappresenta "da scartare"? | ADR-013 |
| 4 | **Crash injection** in ogni punto di un lotto di operazioni su file, seguito da recupero | Il lotto è davvero recuperabile? La compensazione è corretta in tutti i punti di interruzione? | ADR-007 |

**Tappa 1 — Il triage a tastiera in piedi da solo.** Apertura cartella, filtro immagini, griglia, anteprima grande, navigazione a frecce, pannello metadati, permessi contestuali. Risolve quattro frustrazioni su cinque ed è già utilizzabile senza nient'altro.

**Tappa 2 — Giudizio e durabilità.** Rating e marcature, filtri, sidecar, stato di sincronizzazione, matrice dei casi. Aggiunge il lavoro che va protetto, sopra un'app che già funziona.

**Tappa 3 — Operazioni massive e duplicati.** Rinomina e smistamento con anteprima, ricontrollo delle precondizioni, registro e recupero; duplicati esatti e quasi-duplicati. È la tappa in cui il contratto di recuperabilità viene messo alla prova sul serio.

**Tappa 4 — Selezione assistita ed editing.** Pipeline di analisi con motivazioni, punteggi versionati; trasformazioni geometriche. È l'ultima perché è quella che dipende da tutte le altre.

### Growth Features (Post-MVP)

- **Supporto RAW** (CR2/CR3, NEF, ARW, DNG, ORF) con gestione delle coppie RAW+JPEG affiancate e sidecar condiviso dalla coppia.
- **Editing non distruttivo**: regolazioni tonali con file affiancato e storico reversibile; l'originale non viene mai toccato.
- **Preset riutilizzabili e condivisibili** per pattern di rinomina e regole di smistamento.
- **Confronto affiancato** di 2-4 immagini con zoom sincronizzato.
- **Ricerca e filtri cross-cartella** sull'indice locale.
- **Parole chiave e tag**: keyword nel sidecar e, su richiesta esplicita e per lotti confermati, scrittura IPTC dentro i file.
- **Classificazione automatica per soggetto** usando la classificazione di sistema.
- **Esportazione** con ridimensionamento, conversione di formato e rimozione selettiva dei metadati sensibili.
- **Vista mappa** per le immagini geolocalizzate.
- **Distribuzione a terzi**: sandbox con cartelle autorizzate dall'utente, aggiornamenti automatici.
- **Operazioni ricorsive** sull'albero delle sottocartelle, con protezioni aggiuntive.

### Vision (Future)

- **Ricerca semantica in linguaggio naturale** sugli embedding già calcolati in locale, senza mai inviare nulla in rete.
- **Assistente di curation**: dall'insieme di un evento propone una selezione ragionata e una struttura di cartelle, spiegando ogni scelta.
- **Cartelle intelligenti** con regole persistenti che si applicano da sole al materiale nuovo.
- **Sincronizzazione dello stato tra più Mac** (i giudizi seguono l'utente, le immagini restano dove sono).
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

- **Dato derivato** — metadati letti dai file, hash, feature print, anteprime, punteggi. Ricalcolabile in qualunque momento: vive in una cache che può essere distrutta senza perdita.
- **Dato autorale** — stelle e marcature. Non esiste altrove: viene scritto **accanto all'immagine** in un sidecar standard.
- **Stato durevole di processo** — registro delle operazioni, lotti incompleti, giudizi in attesa di scrittura o con scrittura fallita. Non è ricalcolabile e non è ancora nel sidecar: **non può stare nella cache eliminabile**, ed è l'errore che questa revisione corregge.

Il contratto complessivo si esprime in tre parole scelte con cura, e nessuna di esse è *garantito*:

- **Ricostruibile** — la cache derivata, in ogni momento e integralmente.
- **Recuperabile** — un lotto di operazioni su file, dopo un arresto in qualunque punto. Non atomico: non esiste una transazione multi-file, quindi ciò che si offre è la ripresa o la compensazione, non l'indivisibilità.
- **Best-effort** — il recupero dell'associazione tra giudizio e immagine nei casi in cui il collegamento diretto è andato perso. Ogni caso è classificato esplicitamente e i casi non supportati sono dichiarati tali.

```text
Cartella su disco  ◀── osservatore FS ──┐
   │  (enumerazione + filtro UTType)     │  eventi = suggerimento
   ▼                                     │  verità = riconciliazione per differenza
Catalogo in memoria                      │  finestra di quiete + TEMPO MASSIMO
   │  identità: primitive di sistema      │  ID legato al volume; ID persi o
   │            (bookmark + identificatori)│  riavvolti, volume smontato, radice
   │            hash = solo best-effort    │  cambiata → riconciliazione completa
   │  validità: mtime + size               │
   │                                       │
   ├────────────┬──────────────────────────┘
   │            │
   │            ▼
   │      Sidecar XMP accanto all'immagine   ◀── giudizi (sede portabile)
   │            │  coordinamento tra processi, versione osservata,
   │            │  scrittura atomica del singolo file, conflitto esplicito
   │            ▼
   │      ┌──────────────────┬─────────────────────────┐
   │      │  DerivedCache    │  DurableState           │
   │      │  eliminabile     │  NON eliminabile        │
   │      │  metadati, hash, │  journal + lotti aperti,│
   │      │  feature print,  │  scritture in attesa o  │
   │      │  punteggi        │  fallite, stato sync    │
   │      └──────────────────┴─────────────────────────┘
   │            ▲
   │            │
   ▼            │
Code separate sotto budget comune misurato
   I/O · decodifica · Vision/CoreML · archivio
   priorità al visibile, banda di ritenzione con isteresi
   │
   ▼
Griglia / Anteprima grande
   │
   │ (su richiesta, su una selezione)
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
   → passi idempotenti registrati uno a uno → completato
   │  (al riavvio: riprende o compensa)
   │  attraverso il livello unico di accesso
   ▼
Cestino di macOS (reversibile per l'utente, non garantito dal sistema)
```

**Pattern Architetturale:** MVVM su SwiftUI con nucleo di dominio in pacchetti SPM indipendenti dalla UI; concorrenza strutturata con attori; code specializzate sotto una politica di budget comune; separazione fisica tra cache derivata e stato durevole; operazioni su file come macchina a stati recuperabile; ogni scrittura sul filesystem attraversa un livello unico.

**Componenti Principali:**

- **`Catalog`** — enumerazione, filtro per `UTType`, **identità** e **validità** come chiavi distinte, ordinamenti e filtri. L'identità usa le primitive che il sistema espone (bookmark persistenti, identificatori di risorsa e di documento, UUID del volume) nella combinazione stabilita dal cancello n°2; l'hash del contenuto è **recupero best-effort**, non identità, e non viene calcolato in anticipo su tutta la cartella. Contiene l'**osservatore** e il **riconciliatore**: l'osservatore smorza e coalesce, il riconciliatore rienumera e calcola la differenza. Nessuna decisione è presa sull'evento in sé.
- **`Metadata`** — lettura di EXIF/IPTC/GPS/TIFF via ImageIO; normalizzazione in un modello tipizzato, tollerante ai metadati assenti.
- **`Sidecar`** — lettura e scrittura dei giudizi in `.xmp` affiancato. Scrittura **atomica sul singolo file** (temporaneo sullo stesso volume + sostituzione atomica) e **conservativa** (i campi sconosciuti sono riletti e riscritti invariati), sotto **coordinamento di sistema tra processi** e con **controllo ottimistico** sulla versione osservata: se il file è cambiato dopo la nostra lettura, si produce un conflitto esplicito e non una sovrascrittura. Non apre mai in scrittura il file immagine.
- **`Thumbnails`** — anteprime da QuickLook Thumbnailing con cache su disco a due misure; decodifica **sempre ridimensionata** via ImageIO, mai a piena risoluzione; cache in memoria con limite di costo e svuotamento sulla pressione di memoria.
- **`Work`** — politica di ammissione del lavoro asincrono. **Non è una coda unica**: sono code specializzate per ingresso/uscita, decodifica, visione artificiale e archivio, con caratteristiche di costo diverse, coordinate da un **budget di memoria comune** con costi **misurati per tipo di lavoro** (le dimensioni in pixel non stimano la memoria di un modello, di una texture o di un contenitore multipagina). Mantiene una **banda di ritenzione con isteresi** attorno alla parte visibile invece di cancellare tutto ciò che esce dallo schermo; avvolge **ogni singolo elemento** in un blocco di rilascio esplicito.
- **`Duplicates`** — duplicati esatti a stadi di costo crescente (dimensione → hash parziale → hash completo solo su collisione); quasi-duplicati per distanza tra feature print combinata alla vicinanza temporale.
- **`Quality`** — analisi del soggetto e della qualità tecnica su immagine ridimensionata; punteggio estetico da modello Core ML come ultimo criterio. Lo stato aperto/chiuso degli occhi è un'**euristica costruita sui landmark**, non un risultato fornito dal sistema, e come tale è dichiarata e calibrata. Il punteggio di qualità di cattura del volto è **olistico** e si sovrappone in parte ai criteri tecnici: la sovrapposizione è dichiarata invece di essere presentata come conferma indipendente. Ogni punteggio memorizzato porta con sé **revisione della visione artificiale, versione del modello, preprocessing, algoritmo e soglie**.
- **`Access`** — livello unico di accesso al filesystem: l'unico punto autorizzato a creare, scrivere, spostare o eliminare. Custodisce i bookmark, la richiesta contestuale dei permessi e la diagnosi di un accesso negato. È il punto d'innesto della futura sandbox.
- **`FileOps`** — **macchina a stati con log di intenti**: registra piano e precondizioni, **ricontrolla le precondizioni dopo il dry-run e prima di agire**, marca il lotto come preparato, esegue passi **idempotenti** registrando ognuno, e al riavvio riprende o compensa. Il sidecar è incluso nel piano del lotto. Il contratto offerto è la **recuperabilità**, non l'atomicità. Scrive esclusivamente attraverso `Access`.
- **`DerivedCache`** — archivio SQLite **eliminabile**: metadati, hash calcolati, feature print, punteggi versionati, copia dei giudizi per filtrare e ordinare. Ricostruibile integralmente per progetto.
- **`DurableState`** — archivio SQLite **separato e non eliminabile dall'interfaccia**: registro delle operazioni, lotti incompleti, giudizi in attesa di scrittura o con scrittura fallita, stato di sincronizzazione per immagine, preferenze autorali. Non ha un pulsante che lo svuota ed è ciò che va incluso in un backup.
- **`UI`** — SwiftUI per struttura, barra laterale, pannelli e dialoghi; ponte AppKit su `NSCollectionView` per la griglia. Mappa dei tasti centralizzata in un unico punto.

### Technology Stack

| Livello | Tecnologia | Versione | Motivazione |
|---|---|---|---|
| Linguaggio | Swift | 6.x (concorrenza stretta) | Unico linguaggio di prima classe per le API di sistema che costituiscono il valore dell'app; la concorrenza strutturata è il modello richiesto dalle pipeline con cancellazione |
| Piattaforma applicativa | AppKit + Swift Concurrency | macOS 15+ | Il target è una sola piattaforma; nessun livello di astrazione multipiattaforma da mantenere |
| Framework di interfaccia | SwiftUI, con ponte AppKit (`NSCollectionView`) per la griglia | macOS 15+ | SwiftUI per pannelli e dialoghi; `NSCollectionView` dove serve riuso di celle su decine di migliaia di elementi |
| Anteprime e decodifica | QuickLook Thumbnailing + ImageIO + Core Image | di sistema | Copertura nativa dei formati senza dipendenze; decodifica ridimensionata e trasformazioni accelerate |
| Identità dei file | Chiavi di risorsa di Foundation (identificatore di risorsa, identificatore di documento, identificatore di volume) + bookmark persistenti | di sistema | Primitive esposte dal sistema al posto di una formulazione artigianale; hanno proprietà di persistenza diverse tra loro, e la combinazione da adottare è l'esito del cancello n°2 |
| Osservazione del filesystem | File System Events con eventi a granularità di file, identificatore d'evento persistito e legato al volume | di sistema | Rilevare le modifiche senza interrogazione periodica e riprendere dopo la chiusura; gli eventi a granularità di file sono deliberatamente molto più numerosi, il che rende necessarie coalescenza e riconciliazione |
| Coordinamento tra processi | `NSFileCoordinator` | di sistema | Meccanismo di sistema per coordinare accessi concorrenti allo stesso file tra applicazioni; coordina, **non** crea una transazione — e questo limite è parte del contratto, non un dettaglio |
| Visione artificiale | Vision (feature print, rilevamento volti, qualità di cattura, landmark) | di sistema | Embedding e analisi volti sul Neural Engine. Fornisce **landmark** oculari, non un classificatore aperto/chiuso: quella conclusione è nostra ed è dichiarata come euristica |
| Modello estetico | Modello open source di image-quality assessment convertito in Core ML | Core ML di sistema | Criterio di gradimento, eseguito **solo su gruppi già formati e solo su richiesta** |
| Giudizi portabili | Sidecar XMP (`xmp:Rating`, rappresentazione dello scarto) come XML affiancato | XMP Basic | Formato standard letto dai principali strumenti fotografici; è XML puro, quindi nessuna dipendenza esterna e nessuna riscrittura del file immagine. L'interoperabilità è un **obiettivo verificato dal cancello n°3**, non una proprietà del formato |
| Archivi locali | SQLite, in **due file distinti** (cache derivata, stato durevole) | 3 (di sistema) | Cicli di vita diversi devono stare in archivi diversi: un solo file rende impossibile offrire "svuota la cache" senza distruggere il registro delle operazioni |
| Accesso ai dati | GRDB.swift | 7.x | Accesso SQLite tipizzato e testabile, con migrazioni versionate e osservazione delle modifiche |
| Autenticazione | Nessuna | — | App locale monoutente, senza account e senza servizi remoti |
| Test | Swift Testing (unità e integrazione) + XCUITest (percorsi critici a tastiera) | di sistema | I moduli SPM sono testabili senza avviare l'interfaccia; XCUITest copre la navigazione a tastiera |
| Test di robustezza | Test di lunga durata su cartella di grandi dimensioni; **iniezione di arresti** in ogni punto di un lotto di operazioni | — | Crescita di memoria, raffiche di eventi e recupero dopo un arresto non emergono in un test unitario |

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
│   ├── Catalog/                  # enumerazione, filtro tipi, identità/validità, osservatore + riconciliatore
│   ├── Metadata/                 # ImageIO -> modello metadati tipizzato
│   ├── Sidecar/                  # XMP affiancato: coordinamento, versione osservata, conflitti
│   ├── Thumbnails/               # QuickLook + cache su disco + decodifica ridimensionata
│   ├── Work/                     # code specializzate, budget misurato, banda di ritenzione
│   ├── Duplicates/               # hash esatti a stadi + clustering quasi-duplicati
│   ├── Quality/                  # Vision, Core Image, Core ML: punteggi scomposti e versionati
│   ├── Access/                   # livello unico di accesso al filesystem, bookmark, permessi
│   ├── FileOps/                  # macchina a stati, log di intenti, passi idempotenti, compensazione
│   ├── DerivedCache/             # SQLite eliminabile: dati ricalcolabili
│   ├── DurableState/             # SQLite durevole: journal, lotti aperti, scritture in attesa, stato sync
│   └── DesignSystem/             # componenti condivisi, tipografia, accessibilità
├── Spikes/                       # i quattro cancelli tecnici: codice, dataset, esiti scritti
│   ├── 01-scale-memory/
│   ├── 02-fsevents-identity/
│   ├── 03-xmp-roundtrip/
│   └── 04-crash-recovery/
├── Tests/
│   ├── Fixtures/                 # raffiche, duplicati, EXIF mancanti, HEIC, orientamenti, sidecar di terzi
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

**Materiale di prova.** Le fixture (raffiche reali, duplicati byte-identici, immagini senza EXIF, HEIC, orientamenti EXIF non standard, sidecar XMP prodotti da strumenti di terze parti) sono versionate nel repository. I cancelli tecnici richiedono in aggiunta materiale che non può essere versionato — un insieme di 50.000 file e volumi di prova esterni, sincronizzati e di rete — la cui procedura di generazione e configurazione è versionata sotto `Spikes/`, insieme all'esito scritto di ogni cancello.

**Strumenti richiesti:** macOS 15 o successivo su Apple Silicon; Xcode 16 o successivo (Swift 6); `swift-format` e SwiftLint per lo stile; `xcodebuild` per build e test da riga di comando; `notarytool` e `create-dmg` per la distribuzione; Python con `coremltools` **solo** in fase di conversione del modello estetico, mai a tempo di esecuzione.

### CI/CD & Deployment

**Strumento di build:** `xcodebuild` (SPM per la risoluzione delle dipendenze dei pacchetti locali e di GRDB).

**Pipeline:** GitHub Actions su runner macOS. Ad ogni push: `swift-format --lint` e SwiftLint → build dei pacchetti SPM → test unitari → build del target applicativo → XCUITest sui percorsi critici a tastiera → **test di iniezione di arresti** sui lotti di operazioni su file, che verificano ripresa e compensazione da ogni punto di interruzione. Su ramo principale e prima di ogni rilascio, in aggiunta: **test di lunga durata** su una cartella generata di grandi dimensioni, con soglie di fallimento dichiarate su occupazione di memoria di picco, crescita dell'occupazione nel tempo, e numero di riconciliazioni prodotte da una raffica sintetica. Su tag di versione: build Release con hardened runtime, firma, notarizzazione, `.dmg` e pubblicazione come artefatto.

**Deployment:** distribuzione **manuale come `.dmg` notarizzato**, non in sandbox. Nessun canale di aggiornamento automatico nell'MVP.

**Infrastruttura di destinazione:** il Mac dell'utente. Nessuna infrastruttura server, nessun servizio remoto, nessuna telemetria.

### Architecture Decision Records (ADR)

- **ADR-001 — App nativa Swift/SwiftUI, non Electron o multipiattaforma.** *Decisione:* nativa. *Motivo:* le capacità portanti sono servizi di sistema accelerati su hardware; in un runtime web andrebbero reimportate come dipendenze pesanti e girerebbero molto più lente, colpendo il rischio primario. *Conseguenza:* il codice non è portabile fuori da macOS — vincolo dichiarato del prodotto, non limite.
- **ADR-002 — Anteprime da QuickLook Thumbnailing, non decodifica propria.** *Decisione:* il servizio di sistema è la sorgente primaria, con ImageIO come riserva e per lo zoom 1:1. *Motivo:* copertura gratuita dei formati e riuso della cache di sistema. *Conseguenza:* si dipende da una qualità non controllata nel dettaglio; accettabile per la griglia, non per lo zoom, dove si decodifica direttamente — sempre a dimensione dichiarata.
- **ADR-003 — Tre nature di dato, due archivi fisici distinti.** *Decisione:* `DerivedCache` (SQLite eliminabile) contiene solo ciò che è ricalcolabile dai file. `DurableState` (SQLite separato, senza pulsante di svuotamento) contiene il registro delle operazioni, i lotti incompleti, i giudizi in attesa di scrittura o con scrittura fallita, lo stato di sincronizzazione e le preferenze autorali. I giudizi già scritti hanno la loro sede portabile nel sidecar (ADR-013). *Motivo:* la revisione precedente aveva separato i giudizi dalla cache ma vi aveva lasciato dentro il journal e le scritture non riuscite, che non sono ricalcolabili da nulla: con un pulsante "svuota indice" in interfaccia, quel pulsante distruggeva la cronologia di annullamento e l'unica copia di alcuni giudizi. Una separazione soltanto logica non basta, perché il comando di svuotamento agisce su un file. *Conseguenza:* due file, due cicli di vita, nessuna transazione che li attraversi — il che è accettabile perché non condividono invarianti; il comando di svuotamento agisce solo sul primo; il secondo è ciò che un backup deve contenere.
- **ADR-004 — Quasi-duplicati tramite feature print di Vision, non hash percettivo artigianale.** *Decisione:* distanza tra embedding di sistema, combinata alla vicinanza temporale EXIF. *Motivo:* qualità superiore su ritagli, esposizioni e piccoli movimenti, con costo sul Neural Engine. *Conseguenza:* la soglia non ha significato assoluto e va calibrata, regolabile con anteprima visiva immediata.
- **ADR-005 — Consenso progressivo ai permessi; nessun Accesso completo al disco obbligatorio.** *Decisione:* `.dmg` notarizzato con hardened runtime, senza App Sandbox; nessuna richiesta di Accesso completo al disco, ma consenso per categoria chiesto contestualmente e accesso concesso dal pannello di apertura o dal trascinamento. Il FDA è un'opzione. *Motivo:* un'app fuori sandbox accede alle cartelle scelte dall'utente senza FDA, che serve solo per ciò che è protetto in modo speciale: chiederlo all'avvio era costo di adozione a beneficio nullo. *Conseguenza:* nessun permesso prima del gesto che lo motiva; un accesso negato produce uno stato spiegato e recuperabile; richieste, bookmark e diagnosi vivono in `Access`, punto d'innesto della futura sandbox. Distribuzione a terzi e Mac App Store restano fuori portata fino alla sandbox.
- **ADR-006 — Il modello estetico gira solo su richiesta, e solo dentro un gruppo già formato.** *Decisione:* mai in scansione di cartella. *Motivo:* protegge il vincolo di latenza. *Conseguenza:* il punteggio estetico non è disponibile come criterio di ordinamento globale finché non esistono prove di prestazione che lo permettano.
- **ADR-007 — Operazioni massive recuperabili, non atomiche.** *Decisione:* `FileOps` è una macchina a stati con log di intenti scritto **prima** dell'azione: piano e precondizioni registrati → **ricontrollo delle precondizioni dopo il dry-run e immediatamente prima di agire** → lotto marcato come preparato → passi **idempotenti** eseguiti e registrati uno a uno → lotto completato. Al riavvio, un lotto non completato viene ripreso o compensato. Le eliminazioni passano dal Cestino di macOS. *Motivo:* la versione precedente prometteva che immagine e sidecar fossero "un'unità indivisibile". Non esiste una transazione che sposti due file — tantomeno ottocento — come un solo commit: un arresto può sempre cadere tra un passo e l'altro. Il journal non rende atomico un lotto, lo rende recuperabile. E l'anteprima obbligatoria, senza ricontrollo delle precondizioni, protegge da un filesystem che nel frattempo può essere cambiato. *Conseguenza:* la parola "indivisibile" esce dal documento; ogni passo deve essere progettato idempotente e compensabile, il che vincola la forma di ogni operazione; il registro vive in `DurableState`; e il contratto verso l'utente è "questo lotto è ripreso o annullato, e ti dico esattamente a che punto era", non "questo lotto è indivisibile". Anche il Cestino è dichiarato per quello che è: il sistema sposta l'elemento e riferisce dove è finito, senza promettere che vi resti o che sia sempre ripristinabile. Verificato dal cancello n°4.
- **ADR-008 — `NSCollectionView` per la griglia, SwiftUI per tutto il resto.** *Decisione:* ponte AppKit limitato alla griglia. *Motivo:* riuso di celle e fluidità su decine di migliaia di elementi. *Conseguenza:* una superficie AppKit da mantenere, confinata a un solo componente con contratto esplicito.
- **ADR-009 — Code specializzate sotto budget comune misurato, con banda di ritenzione.** *Decisione:* il lavoro asincrono non passa da una coda unica ma da **code separate** — ingresso/uscita, decodifica, visione artificiale e modelli, archivio — con caratteristiche di costo diverse, coordinate da una politica di **budget di memoria comune** i cui costi per tipo di lavoro sono **misurati**, non dedotti. Attorno alla parte visibile si mantiene una **banda di ritenzione con isteresi**; ogni elemento è avvolto in un blocco di rilascio esplicito; la decodifica è sempre a dimensione dichiarata; il budget si riduce sotto pressione di memoria del sistema. *Motivo:* la versione precedente prescriveva un punto unico di ammissione, che concentra in un solo componente la conoscenza di ogni tipo di lavoro e ne fa un collo di bottiglia; e stimava la memoria dalle dimensioni in pixel, che non dicono nulla sul costo di un modello Core ML, di una texture GPU, di un contenitore multipagina o di una risorsa di sistema. Prescriveva inoltre la cancellazione immediata di ciò che esce dallo schermo, che su uno scroll reale ributta via il lavoro appena fatto. *Conseguenza:* nessun componente avvia lavoro fuori dalle code; il budget e i costi per tipo sono parametri misurati dal cancello n°1 e non costanti scelte a intuito; **l'ampiezza della banda di ritenzione è un parametro del budget, non una costante dell'interfaccia**, e le due decisioni vanno calibrate insieme; il test di lunga durata è parte del contratto.
- **ADR-010 — Le regole sono dati, non codice.** *Decisione:* pattern di rinomina e regole di smistamento come strutture serializzabili con grammatica dichiarata. *Motivo:* rende possibili preset, condivisione e cartelle intelligenti senza riscrivere il motore. *Conseguenza:* la grammatica dei token va specificata e versionata (FR-029/FR-035).
- **ADR-011 — Identità dalle primitive di sistema; conservazione dei giudizi come matrice di casi, non come promessa.** *Decisione:* l'identità del file si costruisce sulle chiavi di risorsa che il sistema espone — identificatore di risorsa, identificatore di documento, identificatore di volume — più i bookmark come forma persistente, nella combinazione stabilita dal cancello n°2. La **validità** resta `mtime + size` e la sua scadenza non tocca mai i giudizi. L'hash del contenuto è **recupero best-effort su materiale già indicizzato**, non identità. Al posto della promessa "i giudizi sopravvivono agli spostamenti esterni" il documento pubblica una **matrice esplicita** che classifica ogni caso come supportato, best-effort o non supportato (FR-049). *Motivo:* tre difetti nella versione precedente. Primo, `volume + inode` era una formulazione artigianale al posto di primitive esistenti, che hanno proprietà di persistenza diverse e note. Secondo, l'hash era giustificato come "già calcolato, costo marginale nullo" mentre il rilevamento dei duplicati lo calcola per intero solo su collisione: renderlo disponibile per tutti significa leggere 50.000 file, cioè violare il vincolo di latenza — e comunque due duplicati esatti condividono l'hash e una modifica del contenuto lo cambia. Terzo, e decisivo: se l'utente sposta nel Finder la sola immagine, il sidecar resta indietro e l'app non osserva la destinazione; nessun meccanismo può recuperare quel caso, quindi prometterlo era falso. *Conseguenza:* la matrice diventa contenuto di prodotto visibile all'utente e non una nota tecnica; l'hash si calcola quando è già necessario per altro, mai in anticipo su tutta la cartella; e le primitive di identità restano un'ipotesi finché il cancello n°2 non le verifica.
- **ADR-012 — Eventi come suggerimento, riconciliazione come verità, con tempo massimo.** *Decisione:* l'osservatore non aggiorna mai il catalogo dal contenuto di un evento: raccoglie, smorza in una **finestra di quiete**, coalesce per ambito, e attiva un **riconciliatore** che rienumera e calcola la differenza. Oltre al debounce esiste un **tempo massimo di riconciliazione**, superato il quale si riconcilia comunque anche se gli eventi continuano ad arrivare. Sono esclusi i file di servizio, i temporanei e di trasferimento incompleto, i nascosti e **le scritture prodotte dall'app stessa**. L'identificatore d'evento è persistito **legato all'UUID del volume**; identificatori eliminati o riavvolti, volumi smontati o ripristinati, cambio della radice osservata e segnalazioni di eventi persi portano tutti alla riconciliazione completa dell'ambito, senza perdere selezione né giudizi. Su volumi di rete e cartelle sincronizzate i file non materializzati sono mostrati come tali e mai scaricati implicitamente. *Motivo:* l'infrastruttura di notifica è rumorosa, coalescente e deliberatamente lacunosa sotto carico, e gli eventi a granularità di file sono molto più numerosi. Un'app che reagisce evento per evento consuma CPU a vuoto, mostra file ancora in scrittura e — scrivendo i propri sidecar — si auto-innesca. E la sola finestra di quiete ha un difetto proprio: **una raffica continua non la raggiunge mai**, quindi durante uno scarico di schede lungo la vista resterebbe indietro a tempo indefinito. *Conseguenza:* il costo di una raffica è limitato superiormente a una riconciliazione per finestra, e la latenza massima dell'aggiornamento è limitata dal tempo massimo; entrambi i parametri sono dichiarati e verificati con raffiche sintetiche; la correttezza della vista non dipende mai dalla completezza degli eventi. Verificato dal cancello n°2.
- **ADR-013 — Giudizi in sidecar XMP, con coordinamento e conflitto esplicito.** *Decisione:* stelle ed etichette sono scritte in un `.xmp` accanto all'immagine, in formato standard. La scrittura è **atomica sul singolo file**, **conservativa** sui campi sconosciuti, coordinata tra processi con il meccanismo di sistema, e protetta da **controllo ottimistico** sulla versione osservata: se il sidecar è cambiato dopo la nostra lettura si genera un **conflitto esplicito**, mai una sovrascrittura silenziosa. Ogni immagine ha uno **stato di sincronizzazione** — pulito, scrittura in attesa, scrittura fallita, conflitto esterno — con revisione, provenienza e ultima versione XMP osservata, custodito in `DurableState`. Il file immagine non viene **mai** aperto in scrittura per un giudizio. La scrittura è disattivabile; su cartelle non scrivibili si degrada allo stato locale, dichiarandolo. *Motivo:* i giudizi devono sopravvivere alla perdita della cache, al cambio di Mac e alla disinstallazione, ed essere leggibili dagli strumenti che l'utente già usa. La versione precedente prescriveva "rileggo e riscrivo invariato ciò che non conosco", che non protegge da un'altra applicazione che scrive tra la nostra lettura e la nostra sostituzione; e risolveva i conflitti con "vince la fonte modificata più di recente", che non è una politica ma una speranza. Scrivere IPTC dentro i file darebbe la stessa portabilità ma richiederebbe di riscrivere immagini che l'utente non ha incluso in nessuna operazione, violando NFR-A4. *Conseguenza:* servono decisioni che una specifica non fornisce — convenzione di nome, collisione tra due immagini con la stessa radice e formati diversi, rappresentazione interoperabile dello scarto (candidato: la convenzione `xmp:Rating = -1`, più uniforme di `xmp:Label`) — e nessuna di esse è considerata risolta finché il cancello n°3 non produce un round-trip su strumenti reali. Il coordinamento di sistema coordina ma non crea una transazione: anche qui il contratto è recuperabilità e conflitto visibile, non atomicità.
- **ADR-014 — Punteggi come euristiche dichiarate e versionate.** *Decisione:* lo stato aperto/chiuso degli occhi è un'**euristica costruita sui landmark** forniti dalla visione artificiale, non un risultato del sistema: è dichiarata come tale, calibrata su occhiali, profilo, occlusioni e volti piccoli, e accompagnata dalla sua affidabilità stimata. Il punteggio di qualità di cattura del volto è **olistico** e si sovrappone a nitidezza ed esposizione calcolate separatamente: la sovrapposizione è misurata e **dichiarata all'utente**, e il ruolo di quel punteggio nella cascata è deciso di conseguenza. Ogni punteggio memorizzato porta con sé **revisione della visione artificiale, versione del modello, preprocessing, algoritmo e soglie**. *Motivo:* presentare un'euristica nostra come capacità di sistema è un errore di categoria che si paga sulla calibrazione; e mostrare due criteri sovrapposti come ragioni indipendenti non è una spiegazione ma una ripetizione travestita da conferma — il che colpisce direttamente il differenziatore n°3, che è la spiegabilità. Infine, senza versionamento il primo aggiornamento di sistema rende i punteggi in cache silenziosamente incomparabili: la cache non è più veloce, è sbagliata. *Conseguenza:* i punteggi in cache si invalidano automaticamente al cambio di una qualunque delle versioni registrate; l'interfaccia deve poter dire "questo punteggio è stato calcolato con una versione precedente"; e la cascata dei criteri va rivista alla luce della sovrapposizione misurata invece di essere assunta come una successione di stadi indipendenti.
- **ADR-015 — Cancelli tecnici prima del full build, e consegna a tappe.** *Decisione:* quattro verifiche precedono la costruzione completa — scala e memoria su 50.000 file, matrice degli eventi e delle identità su APFS/esterno/sincronizzato/di rete, round-trip XMP con strumenti reali e scrittura concorrente, iniezione di arresti in ogni punto di un lotto seguita da recupero. Ognuna produce un esito scritto che conferma o modifica gli ADR corrispondenti. Lo scope non è ridotto, ma la costruzione segue quattro tappe consegnabili e utilizzabili una per volta (vedi *Percorso di consegna*). *Motivo:* due revisioni indipendenti hanno osservato che l'insieme è più vicino a una prima versione professionale che a un minimo prodotto, e che dichiarare il costo affronta il rischio di sforzo ma non quello di **integrazione**: browser performante, sistema di metadati, motore di operazioni recuperabili, interoperabilità XMP, rilevatore di duplicati, pipeline di modelli, editor e accessibilità hanno modalità di guasto diverse e verrebbero integrati per la prima volta insieme. Ognuno dei quattro cancelli può invalidare un ADR, e scoprirlo dopo aver costruito sopra costa molte volte tanto. *Conseguenza:* l'inizio della costruzione completa è subordinato all'esito dei cancelli, e questo è un ritardo dichiarato e voluto; gli ADR-007, 009, 011, 012 e 013 sono formalmente **provvisori** fino al cancello corrispondente; e ogni tappa deve essere consegnabile da sola, il che vincola l'ordine delle dipendenze fin dalla progettazione.

---

## Functional Requirements

<!-- archetipo:prd section=functional_requirements required=true -->

### Area 1 - Apertura e navigazione delle cartelle

- **FR-001** L'utente può aprire una cartella trascinandola sull'app o sulla sua icona, tramite il dialogo di apertura di sistema, dalle cartelle recenti o dai preferiti nella barra laterale.
- **FR-002** La vista mostra **esclusivamente** i file riconosciuti come immagini secondo il tipo di sistema (`UTType`), non secondo l'estensione.
- **FR-003** L'app indica quanti elementi non-immagine sono presenti nella cartella, senza mescolarli mai al contenuto visibile, distinguendo i **file collegati** (sidecar delle immagini presenti) dal resto del contenuto estraneo.
- **FR-004** L'utente può ordinare per nome, data di scatto, data di modifica, dimensione file e rating, in ordine crescente o decrescente, e l'ordinamento persiste tra le sessioni.
- **FR-005** L'app ricorda le cartelle aperte di recente e permette di fissare cartelle preferite nella barra laterale; i riferimenti sono persistiti in forma che resta valida quando la cartella viene rinominata o spostata sullo stesso volume, e che segnala esplicitamente quando non è più risolvibile.

### Area 2 - Osservazione della cartella e sincronizzazione

- **FR-006** L'app rileva le modifiche alla cartella aperta (file aggiunti, rimossi, rinominati, modificati da altre applicazioni) e aggiorna la vista senza intervento dell'utente, **senza perdere la selezione corrente** né la posizione di scorrimento.
- **FR-007** Gli eventi del filesystem non aggiornano mai direttamente il catalogo: attivano una **riconciliazione** che rienumera l'ambito interessato e ne calcola la differenza rispetto allo stato conosciuto. La vista riflette sempre il risultato della riconciliazione, mai il contenuto grezzo di un evento.
- **FR-008** Gli eventi sono smorzati in una **finestra di quiete** e coalescenti per ambito: una raffica di modifiche entro la finestra produce **una sola** riconciliazione. Un file ancora in scrittura è considerato solo quando dimensione e data di modifica si sono stabilizzate.
- **FR-009** Esiste un **tempo massimo** oltre il quale la riconciliazione avviene comunque, anche se gli eventi continuano ad arrivare senza interruzione. Un'importazione lunga non può rimandare l'aggiornamento della vista a tempo indefinito.
- **FR-010** L'app ignora i file di servizio del sistema, i temporanei e di trasferimento incompleto, i nascosti e **le scritture prodotte dall'app stessa** — in particolare i sidecar appena salvati — così che nessuna di queste provochi aggiornamenti o consumo di risorse.
- **FR-011** L'app gestisce esplicitamente le condizioni in cui la cronologia degli eventi non è affidabile: segnalazione di eventi persi, identificatori eliminati o riavvolti, cambio della cartella osservata. In ognuna riconcilia integralmente l'ambito senza perdere selezione, giudizi né risultati già calcolati.
- **FR-012** L'identificatore dell'ultimo evento elaborato è persistito **insieme all'identità del volume** a cui appartiene, e non viene applicato a un volume diverso. Smontaggio, rimontaggio o ripristino di un volume portano a riconciliazione anziché a interpretazione di identificatori non più validi.
- **FR-013** Le modifiche avvenute mentre l'app era chiusa sono rilevate alla riapertura riprendendo dagli eventi quando disponibili e riconciliando in ogni caso; l'utente non deve mai svuotare la cache per vedere la cartella aggiornata.
- **FR-014** Su volumi di rete e cartelle gestite da servizi di sincronizzazione, i file non ancora materializzati sono mostrati come tali e **non vengono scaricati implicitamente** dall'app: nessuna operazione di sola visualizzazione provoca un trasferimento di rete non richiesto.
- **FR-015** L'osservazione è attiva sulla sola cartella aperta, non discende ricorsivamente nelle sottocartelle, ed è sospesa quando nessuna cartella è aperta.

### Area 3 - Visualizzazione

- **FR-016** La griglia mostra le anteprime con dimensione della cella regolabile su almeno cinque livelli, fino a permettere di valutare la nitidezza senza aprire l'immagine.
- **FR-017** La griglia resta fluida durante lo scorrimento su cartelle di almeno 10.000 immagini, caricando le anteprime di ciò che è visibile e imminente e liberando ciò che è ampiamente fuori vista.
- **FR-018** L'utente può aprire un'anteprima grande dell'immagine selezionata, a pannello o a schermo intero, con un solo tasto.
- **FR-019** Nell'anteprima grande l'utente può ingrandire fino alla scala 1:1 dei pixel e spostarsi nell'immagine, per valutare fuoco e dettaglio.
- **FR-020** Le immagini sono visualizzate rispettando l'orientamento EXIF e il profilo colore incorporato.
- **FR-021** L'app segnala visivamente le immagini per cui non è possibile generare un'anteprima o leggere il contenuto, senza interrompere il caricamento delle altre.

### Area 4 - Navigazione da tastiera

- **FR-022** L'utente può spostare la selezione con i soli tasti freccia, sia in griglia (movimento bidimensionale) sia in anteprima grande (immagine precedente e successiva).
- **FR-023** L'utente può estendere la selezione da tastiera, selezionare tutto e invertire la selezione.
- **FR-024** Tutte le azioni dell'MVP — anteprima grande, pannello metadati, rating, marcatura, spostamento nel Cestino, rinomina, avvio dell'analisi — sono attivabili da tastiera senza usare il mouse.
- **FR-025** L'app espone un pannello di aiuto che elenca tutte le scorciatoie attive, richiamabile con un tasto.

### Area 5 - Metadati

- **FR-026** Un pannello metadati, mostrabile e nascondibile con un tasto, presenta per l'immagine selezionata: nome e percorso, dimensione del file, dimensioni in pixel, formato, date di creazione e modifica, spazio colore.
- **FR-027** Lo stesso pannello mostra i dati EXIF disponibili — fotocamera, obiettivo, ISO, tempo, diaframma, focale, data e ora di scatto, orientamento — e i dati IPTC e GPS quando presenti, indicando esplicitamente i campi assenti anziché ometterli silenziosamente.
- **FR-028** Il pannello si aggiorna al cambio di selezione senza latenza percepibile; con selezione multipla mostra i valori comuni e segnala i divergenti. L'utente può copiare un singolo campo o l'intero blocco.

### Area 6 - Rinomina massiva (capacità a)

- **FR-029** L'utente può rinominare una selezione applicando un pattern composto da testo libero e token. I token supportati nell'MVP sono almeno:

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

- **FR-030** L'app mostra **obbligatoriamente** un'anteprima `nome attuale → nome nuovo` per ogni file coinvolto prima di eseguire qualsiasi rinomina, evidenziando collisioni, caratteri non ammessi, nomi troppo lunghi e ricadute su dati mancanti.
- **FR-031** L'utente sceglie esplicitamente la politica per le collisioni: suffisso progressivo, salto del file, o annullamento del lotto. Il valore predefinito non sovrascrive mai un file esistente.
- **FR-032** L'estensione originale è preservata e non è modificabile dal pattern.
- **FR-033** Ogni lotto di rinomina è registrato prima dell'esecuzione ed è annullabile anche dopo la chiusura e riapertura dell'app, con il contratto di recuperabilità di FR-072: l'annullamento riporta ciò che è ripristinabile e dichiara esattamente ciò che non lo è.

### Area 7 - Smistamento in sottocartelle (capacità b)

- **FR-034** L'utente può generare sottocartelle e spostarvi le immagini secondo una regola scelta tra: data di scatto (anno, anno-mese, anno-mese-giorno), fotocamera, formato, rating, marcatura da scartare.
- **FR-035** Il nome delle sottocartelle è definibile con la stessa grammatica di token della rinomina massiva.
- **FR-036** L'app mostra obbligatoriamente l'anteprima dell'albero risultante — quali cartelle verranno create e quanti file finiranno in ciascuna — prima di eseguire qualsiasi spostamento.
- **FR-037** Le immagini per cui la regola non è applicabile finiscono in una cartella di raccolta con nome configurabile, e non restano mai in stato indeterminato.
- **FR-038** Anche lo smistamento è registrato e annullabile con lo stesso contratto della rinomina (FR-033).
- **FR-039** Nell'MVP le operazioni massive agiscono sulla cartella corrente e non discendono ricorsivamente nelle sottocartelle; il limite è dichiarato in interfaccia.

### Area 8 - Giudizio, marcatura e filtri

- **FR-040** L'utente può assegnare un rating da 1 a 5 stelle, rimuoverlo, e marcare o smarcare un'immagine come "da scartare", con un singolo tasto e senza lasciare la posizione corrente.
- **FR-041** L'assegnazione è immediata nell'interfaccia e non attende il completamento della scrittura su disco; lo stato di scrittura è visibile secondo FR-046.
- **FR-042** L'utente può filtrare per rating (minimo, esatto), marcatura, formato e intervallo di date, e combinare i filtri.

### Area 9 - Durabilità e portabilità dei giudizi

- **FR-043** Rating e marcature sono scritti in un **sidecar XMP** affiancato all'immagine, in formato standard leggibile dai principali strumenti fotografici, oltre a essere mantenuti nello stato locale per filtrare e ordinare rapidamente.
- **FR-044** L'app **non apre mai in scrittura il file immagine** per registrare un giudizio. La scrittura del sidecar è atomica sul singolo file: un'interruzione non può produrre un sidecar parziale né alterare l'immagine.
- **FR-045** La scrittura del sidecar è coordinata con le altre applicazioni tramite il meccanismo di sistema e protetta da controllo sulla versione osservata: se il file è cambiato dopo la nostra lettura, l'app **non sovrascrive** ma segnala un conflitto.
- **FR-046** Ogni immagine ha uno **stato di sincronizzazione esplicito e visibile** — allineato, scrittura in attesa, scrittura fallita, conflitto esterno — con l'indicazione di cosa lo ha determinato. Nessun conflitto viene risolto in silenzio; l'utente vede i valori in gioco e decide, oppure conferma la risoluzione proposta.
- **FR-047** Alla lettura, l'app riconosce i sidecar già presenti, compresi quelli prodotti da altri strumenti, e ne importa rating ed etichetta. I campi che non conosce sono **conservati invariati** quando riscrive il file.
- **FR-048** Ogni operazione su file include il sidecar nel piano del lotto, nella sua anteprima e nel suo registro, e lo ripristina insieme all'immagine in caso di annullamento. Il contratto è quello di FR-072: **recuperabilità**, non indivisibilità — un'interruzione può lasciare immagine e sidecar in posizioni diverse, e in quel caso l'app lo rileva e lo riporta invece di nasconderlo.
- **FR-049** L'app pubblica, in interfaccia e non solo in documentazione, la **matrice dei casi** di conservazione del giudizio, con tre livelli espliciti:

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

- **FR-050** Il recupero best-effort si applica solo a materiale già presente nella cache derivata e non comporta in nessun caso la lettura integrale anticipata dell'intera cartella. L'app dichiara quando un'associazione è stata ricostruita per tentativo anziché per collegamento diretto.
- **FR-051** La scrittura dei sidecar è disattivabile dalle impostazioni. Quando la cartella non è scrivibile, i giudizi restano nello stato locale e l'app dichiara che su quella cartella non sono portabili, senza presentarlo come un errore.
- **FR-052** L'interfaccia dichiara in modo comprensibile dove vivono i giudizi, cosa comporta disattivare i sidecar, e quale parte dello stato locale il comando di svuotamento **non** tocca.

### Area 10 - Duplicati

- **FR-053** L'app individua i **duplicati esatti** all'interno della selezione o della cartella corrente, procedendo per stadi di costo crescente e senza leggere integralmente file che possono essere esclusi prima.
- **FR-054** I duplicati esatti sono presentati in gruppi con un candidato da tenere proposto secondo criteri dichiarati (percorso più stabile, nome più informativo, data più antica, presenza di un giudizio già assegnato), sempre modificabile dall'utente.
- **FR-055** L'app individua i **gruppi di quasi-duplicati** combinando similarità visiva e vicinanza temporale, con soglia regolabile e riorganizzazione visiva immediata al variare della soglia.
- **FR-056** Nessun duplicato viene eliminato senza conferma esplicita; l'eliminazione passa dal Cestino di macOS.

### Area 11 - Selezione assistita (capacità c)

- **FR-057** Data una selezione, l'utente può chiedere le **N migliori da tenere** (N predefinito 3, regolabile almeno tra 1 e 10).
- **FR-058** L'analisi procede nell'ordine stabilito: (1) raggruppamento per similarità visiva e temporale, (2) valutazione del soggetto — volti rilevati, qualità del volto, stima di occhi aperti o chiusi, (3) qualità tecnica misurabile — nitidezza valutata sul soggetto e non sull'intero fotogramma, mosso, esposizione e clipping, rumore stimato, (4) punteggio estetico come spareggio finale.
- **FR-059** Per **ogni** immagine valutata l'app mostra il punteggio scomposto nei criteri che lo compongono, in forma leggibile, e non un singolo numero opaco.
- **FR-060** Dove due criteri si sovrappongono — in particolare il punteggio complessivo del volto rispetto a nitidezza ed esposizione calcolate separatamente — l'app **dichiara la sovrapposizione** invece di presentarli come conferme indipendenti, e non conta due volte la stessa grandezza nella graduatoria.
- **FR-061** La stima di occhi aperti o chiusi è presentata come **valutazione dell'app con affidabilità dichiarata**, non come dato certo, ed è verificabile dall'utente sull'anteprima grande.
- **FR-062** L'app dichiara sempre **perché** un'immagine è stata proposta e perché un'altra è stata scartata, in termini di criteri, così che l'utente possa dissentire con cognizione.
- **FR-063** Ogni punteggio memorizzato porta con sé la versione degli strumenti che lo hanno prodotto — revisione della visione artificiale, versione del modello, preprocessing, algoritmo e soglie. Al cambiare di una di esse i punteggi non sono più considerati validi e l'app lo indica anziché confrontare valori incomparabili.
- **FR-064** L'utente può modificare la proposta prima di agire, e nessuna immagine viene eliminata o spostata senza conferma esplicita.
- **FR-065** L'analisi è eseguita **solo su richiesta e solo su una selezione**: aprire una cartella non innesca in nessun caso il calcolo dei punteggi.
- **FR-066** L'analisi è annullabile in qualunque momento, mostra un avanzamento leggibile, e i risultati parziali restano validi e memorizzati.
- **FR-067** Tutta l'analisi avviene in locale: nessuna immagine, nessun dato derivato e nessun metadato lascia il dispositivo in nessuna circostanza.

### Area 12 - Editing di base

- **FR-068** L'utente può ruotare un'immagine di 90° in entrambi i versi e capovolgerla orizzontalmente e verticalmente, anche su selezioni multiple.
- **FR-069** L'utente può ritagliare con proporzioni libere o predefinite (1:1, 4:3, 3:2, 16:9), con riquadro trascinabile e valori visibili.
- **FR-070** Al salvataggio l'utente sceglie esplicitamente tra sovrascrivere l'originale e creare una copia; l'opzione predefinita è la copia. Creando una copia, il giudizio dell'immagine di partenza è replicato sulla copia insieme al suo sidecar.
- **FR-071** Il salvataggio preserva i metadati EXIF/IPTC di partenza, aggiornando i soli campi resi incoerenti dalla trasformazione (dimensioni, orientamento).

### Area 13 - Operazioni su file e reversibilità

- **FR-072** Ogni lotto di operazioni su file segue un contratto dichiarato: piano e precondizioni registrati prima di agire, **precondizioni ricontrollate immediatamente prima dell'esecuzione** e non solo al momento dell'anteprima, passi eseguiti in modo idempotente e registrati uno a uno. Un'interruzione in qualunque punto lascia il lotto in uno stato riconoscibile, che alla riapertura viene **ripreso o compensato**. Il contratto offerto è la recuperabilità: l'app non promette che un lotto sia indivisibile, promette di sapere sempre a che punto era e di poterlo concludere o riportare indietro.
- **FR-073** Se tra l'anteprima e l'esecuzione le precondizioni sono cambiate — file spostati, rinominati, resi non scrivibili, o comparsi con lo stesso nome di destinazione — l'app **interrompe prima di agire** e ripresenta l'anteprima aggiornata, invece di procedere su un piano non più valido.
- **FR-074** L'utente può spostare, copiare e rinominare singole immagini e selezioni verso una destinazione scelta, con gestione esplicita delle collisioni.
- **FR-075** L'eliminazione avviene **sempre tramite il Cestino di macOS** e mai con cancellazione diretta. L'app dichiara che il ripristino dal Cestino resta nelle mani dell'utente e del sistema: l'elemento vi viene spostato, ma l'app non può promettere che vi rimanga.
- **FR-076** L'app espone una cronologia delle operazioni massive, con la possibilità di annullare un lotto specifico e non solo l'ultimo. L'annullamento dichiara esattamente cosa ha ripristinato e cosa non ha potuto ripristinare, e perché.
- **FR-077** Ogni operazione riporta un esito esplicito: quanti file elaborati, saltati, in errore e per quale motivo. Un errore su un singolo file non interrompe il lotto né lo lascia in stato indeterminato.
- **FR-078** L'utente può rivelare qualsiasi immagine nel Finder e aprirla con un'altra applicazione, senza perdere lo stato dell'app.

### Area 14 - Archivi locali, identità e prestazioni

- **FR-079** L'app mantiene **due archivi locali distinti**: una **cache derivata**, che contiene solo dati ricalcolabili dai file, e uno **stato durevole**, che contiene il registro delle operazioni, i lotti non completati, i giudizi non ancora scritti nei sidecar o con scrittura fallita, e lo stato di sincronizzazione.
- **FR-080** Il comando di svuotamento agisce **esclusivamente sulla cache derivata**. Lo stato durevole non è cancellabile dall'interfaccia, e l'app dichiara prima dell'operazione cosa viene eliminato e cosa resta.
- **FR-081** L'archivio distingue **identità** e **validità** come informazioni separate: l'identità determina a chi appartengono i giudizi, la validità determina cosa va ricalcolato. La scadenza della validità invalida i dati derivati e **non tocca mai i giudizi**.
- **FR-082** Alla riapertura di una cartella già indicizzata, la griglia è popolata dalla cache senza ricalcoli, e le modifiche avvenute nel frattempo sono riconciliate in sottofondo senza bloccare l'interazione.
- **FR-083** Il caricamento in sottofondo mantiene una **banda attorno alla parte visibile**, con soglie di entrata e uscita diverse, in modo che un piccolo movimento di scorrimento non provochi la perdita e il ricalcolo del lavoro appena svolto.

### Area 15 - Permessi e primo avvio

- **FR-084** L'app non richiede l'Accesso completo al disco per funzionare, e non ne fa un prerequisito di primo avvio: l'utente apre una cartella e lavora.
- **FR-085** Ogni richiesta di accesso avviene **dopo il gesto che la motiva** — l'apertura o il trascinamento di una cartella — e mai su una schermata preliminare; la motivazione mostrata nel dialogo di sistema spiega in una frase perché serve.
- **FR-086** Se l'accesso viene negato, l'app mostra uno stato che spiega cosa manca e come concederlo, con una via diretta al pannello di sistema corrispondente, e resta pienamente utilizzabile sulle cartelle già accessibili.
- **FR-087** L'app offre, come opzione e non come obbligo, la concessione dell'Accesso completo al disco per chi lavora su percorsi insoliti, spiegando cosa cambia in concreto.

### Area 16 - Accessibilità

- **FR-088** Ogni funzione dell'MVP è raggiungibile da tastiera; nessuna azione richiede esclusivamente il mouse o il trackpad.
- **FR-089** Le immagini in griglia, i controlli e i campi del pannello metadati espongono etichette leggibili da VoiceOver; il valore dei metadati, il giudizio assegnato e il suo stato di sincronizzazione sono annunciabili senza aprire finestre aggiuntive.
- **FR-090** L'app rispetta le preferenze di sistema *Riduci movimento* e *Aumenta contrasto*, e supporta la dimensione del testo di sistema nei pannelli senza troncamenti.

---

## Non-Functional Requirements

<!-- archetipo:prd section=non_functional_requirements required=true -->

### Prestazioni e reattività

Sono i requisiti che governano il rischio primario del prodotto e vanno trattati come vincoli, non come obiettivi. I valori numerici sono **da confermare dal cancello tecnico n°1**: sono soglie dichiarate, non misure già ottenute.

- **NFR-P1** Alla prima apertura di una cartella con 3.000 immagini, la prima schermata di anteprime è visibile entro **1 secondo**; la griglia è navigabile mentre il resto continua a caricarsi in sottofondo.
- **NFR-P2** Alla riapertura di una cartella già indicizzata la griglia è popolata **immediatamente** dalla cache; l'eventuale riconciliazione delle modifiche avvenute nel frattempo avviene in sottofondo e non ritarda la prima schermata.
- **NFR-P3** Lo spostamento della selezione con le frecce risponde entro **100 ms** anche mentre sono in corso lavori in sottofondo; l'interfaccia non si blocca mai.
- **NFR-P4** Il pannello metadati si aggiorna entro **150 ms** dal cambio di selezione.
- **NFR-P5** Nessuna scansione bloccante all'apertura di una cartella: enumerazione, metadati, hash e analisi visiva sono lavori annullabili a priorità inferiore all'interazione.
- **NFR-P6** Il lavoro in sottofondo relativo a ciò che è **ampiamente fuori** dalla parte visibile è annullato, mantenendo una banda di ritenzione con soglie di entrata e uscita distinte; la coda non cresce indefinitamente con lo scorrimento, e un piccolo movimento non provoca la perdita del lavoro appena svolto.
- **NFR-P7** L'occupazione di memoria resta stabile su cartelle da 10.000 immagini: le anteprime sono liberate al di fuori della banda di ritenzione.
- **NFR-P8** Il rilevamento dei duplicati esatti su 10.000 file non legge integralmente i file che possono essere esclusi negli stadi precedenti. Nessun calcolo di hash è eseguito in anticipo sull'intera cartella per scopi diversi dal rilevamento richiesto.
- **NFR-P9 Tetto di memoria dichiarato e verificato.** Esiste un limite superiore dichiarato all'occupazione di picco su una cartella da 50.000 immagini con scorrimento continuo, e una sessione di lunga durata non mostra crescita monotona dell'occupazione. Entrambe le soglie sono verificate da un test automatico che fallisce la build quando vengono superate.
- **NFR-P10 Il parallelismo è derivato da costi misurati, non stimati.** Il lavoro passa da code specializzate per tipo, ammesse entro un budget di memoria comune i cui costi per tipo di lavoro sono **misurati su hardware reale** e non dedotti dalle dimensioni in pixel. Il budget si riduce sotto pressione di memoria del sistema. Nessuna immagine viene decodificata a piena risoluzione quando ne basta una ridimensionata.
- **NFR-P11 Quiete a riposo e latenza massima dell'aggiornamento.** Con una cartella aperta e ferma, l'uso di CPU è indistinguibile da zero. Una raffica di modifiche produce **al massimo una riconciliazione per finestra di quiete**, e in ogni caso **almeno una entro il tempo massimo dichiarato**, anche se la raffica non si interrompe mai. Entrambi verificati con raffiche sintetiche.
- **NFR-P12 La banda di ritenzione è un parametro del budget.** La sua ampiezza è memoria occupata di proposito e viene calibrata insieme al budget di memoria, non scelta indipendentemente come costante dell'interfaccia.

### Affidabilità e integrità dei dati

- **NFR-A1** Nessuna operazione distruttiva senza conferma esplicita; nessuna eliminazione fuori dal Cestino di macOS.
- **NFR-A2** Ogni operazione massiva è preceduta da un'anteprima completa dell'effetto, da un **ricontrollo delle precondizioni immediatamente prima di agire**, e da una registrazione persistente che ne consente la ripresa o la compensazione dopo un riavvio. Il registro include i file collegati mossi insieme alle immagini.
- **NFR-A3 Il contratto è la recuperabilità, non l'atomicità.** L'app non dichiara in nessun punto che un insieme di file venga modificato in modo indivisibile, perché il filesystem non offre questa proprietà su più file. Dichiara invece che dopo un'interruzione in qualunque punto è in grado di riconoscere lo stato raggiunto e di concludere o riportare indietro il lotto, riferendo esattamente cosa è riuscito e cosa no.
- **NFR-A4** L'app non modifica mai un file che l'utente non ha esplicitamente incluso in un'operazione. In particolare, registrare un giudizio non comporta **in nessun caso** la riscrittura del file immagine.
- **NFR-A5** Un file corrotto o illeggibile non compromette il caricamento della cartella né alcuna operazione sugli altri file. Lo stesso vale per un sidecar malformato o scritto da uno strumento sconosciuto: viene segnalato e ignorato, mai riscritto alla cieca.
- **NFR-A6** La scrittura di un sidecar è atomica sul singolo file: un arresto anomalo non può produrre un sidecar parziale né perdere il giudizio precedente.
- **NFR-A7** Nessuna perdita silenziosa di un giudizio: una scrittura fallita lascia il giudizio nello stato durevole, è visibile all'utente ed è riprovabile.
- **NFR-A8** Nessun conflitto risolto in silenzio: quando la versione sul disco è cambiata dopo la nostra lettura, l'app segnala il conflitto e mostra i valori in gioco anziché sovrascrivere.
- **NFR-A9** La correttezza della vista non dipende dalla completezza delle notifiche del filesystem: in ogni condizione — eventi persi, identificatori riavvolti, volume rimontato — una riconciliazione riporta il catalogo in accordo con il disco.
- **NFR-A10** Il comando di svuotamento della cache non può in nessun caso rimuovere il registro delle operazioni, un lotto non completato o un giudizio non ancora scritto nel suo sidecar. Questa proprietà è garantita dalla separazione fisica degli archivi ed è coperta da test dedicati.
- **NFR-A11** Nessun punteggio in cache è confrontato con uno calcolato da una versione diversa degli strumenti o delle soglie: al cambio di versione i valori sono considerati non validi e ricalcolati o segnalati come tali.

### Sicurezza

- **NFR-S1 Nessuna rete a tempo di esecuzione.** L'app non invia immagini, metadati, dati derivati né telemetria a nessun servizio remoto. L'unica connessione ammessa è l'eventuale download iniziale del modello estetico, se non incluso nel bundle: esplicita, verso un'origine dichiarata, verificata per integrità e rinunciabile. Sono escluse anche le materializzazioni implicite di file remoti causate dalla sola visualizzazione (FR-014).
- **NFR-S2 Nessun account, nessuna credenziale, nessun dato personale raccolto.** Non esiste autenticazione perché non esiste nulla da autenticare.
- **NFR-S3 Distribuzione firmata.** Binario firmato con hardened runtime e notarizzato da Apple; nessuna disattivazione di Gatekeeper richiesta all'utente.
- **NFR-S4 Permesso minimo necessario.** L'app opera senza sandbox ma **non richiede l'Accesso completo al disco**: si affida al consenso contestuale per le categorie protette e all'accesso concesso aprendo o trascinando una cartella. Il permesso più ampio è un'opzione, mai un prerequisito.
- **NFR-S5 Punto unico di scrittura.** Tutte le scritture, gli spostamenti e le eliminazioni passano da un unico livello di accesso al filesystem, coperto da test dedicati, che è anche il punto d'innesto della futura sandbox.
- **NFR-S6 Dati sensibili nei metadati.** Le coordinate GPS sono trattate come informazione sensibile: mostrate su richiesta, mai incluse in nomi generati automaticamente, mai copiate in un sidecar, e rimovibili in esportazione (fase di crescita).
- **NFR-S7 Superficie delle dipendenze ridotta al minimo.** L'unica dipendenza esterna a tempo di esecuzione è GRDB.swift; tutto il resto è framework di sistema, e il formato dei sidecar è XML gestito senza librerie di terze parti. Ogni nuova dipendenza richiede una decisione architetturale registrata.
- **NFR-S8 Provenienza del modello.** Il modello estetico open source è versionato, la sua licenza è verificata come compatibile con la distribuzione, e la sua origine e conversione sono documentate nel repository.

### Integrazioni

Tutte le integrazioni sono con il sistema operativo o con formati standard aperti; non esiste alcuna integrazione con servizi di terze parti.

- **NFR-I1 QuickLook Thumbnailing** — generazione delle anteprime per i formati supportati dal sistema, con riuso della cache di sistema.
- **NFR-I2 ImageIO** — lettura di metadati EXIF/IPTC/GPS/TIFF, decodifica sempre ridimensionata, scrittura in fase di salvataggio con preservazione dei metadati.
- **NFR-I3 Vision** — feature print per la similarità visiva, rilevamento volti, qualità di cattura del volto, **landmark** oculari. Lo stato aperto/chiuso degli occhi **non** è fornito dal sistema: è un'euristica dell'app costruita sui landmark, dichiarata e calibrata come tale (ADR-014).
- **NFR-I4 Core ML** — esecuzione locale del modello estetico, su richiesta e su insiemi già ridotti.
- **NFR-I5 Core Image e Metal** — trasformazioni geometriche, istogrammi, misure di nitidezza, con accelerazione GPU.
- **NFR-I6 File System Events** — rilevamento delle modifiche alla cartella aperta, con eventi a granularità di file, identificatore d'evento persistito e legato al volume, e gestione esplicita di eventi persi, identificatori non più validi e volumi smontati o ripristinati.
- **NFR-I7 Coordinamento file di sistema** — coordinamento degli accessi concorrenti al sidecar tra applicazioni diverse. Coordina, **non** crea una transazione: il contratto che ne deriva è conflitto visibile e recuperabilità, non atomicità.
- **NFR-I8 Cestino di macOS** — unica via di eliminazione. Il sistema sposta l'elemento nel Cestino e riferisce dove è finito; il ripristino resta nelle mani dell'utente e del sistema e non è promesso dall'app.
- **NFR-I9 XMP (schema Basic)** — formato standard aperto per rating e rappresentazione dello scarto nei sidecar. L'interoperabilità con Bridge, Lightroom, darktable e digiKam è un **obiettivo verificato da test di round-trip reali** (cancello n°3), non una proprietà che il formato garantisca da solo.
- **NFR-I10 Chiavi di risorsa di Foundation** — identità e validità dei file dalle primitive di sistema anziché da formulazioni artigianali; la combinazione adottata è l'esito del cancello n°2.
- **NFR-I11 Servizi Finder** — rivela nel Finder, apri con, foglio di condivisione di sistema.
- **NFR-I12 Accessibilità di sistema** — VoiceOver, *Riduci movimento*, *Aumenta contrasto*, dimensione del testo.
- **NFR-I13 Nessuna integrazione con la libreria Foto di macOS** nell'MVP: scelta esplicita coerente con "la cartella è la fonte di verità".

---

## Next Steps

<!-- archetipo:prd section=next_steps required=true -->

1. **Cancelli tecnici** - Esegui i quattro spike di Tappa 0 e registrane l'esito: possono modificare ADR-007, 009, 011, 012 e 013 prima che venga scritta una riga di applicazione
2. **Backlog** - Esegui `/archetipo-spec` per trasformare questo PRD in un backlog, con le tappe di consegna come struttura portante
3. **Design** - Esegui `/archetipo-design` per i mockup dell'interfaccia (quando applicabile)
4. **Validazione** - Rivedi con gli stakeholder e metti alla prova gli assunti più rischiosi

---

_PRD generato tramite ARchetipo Product Inception - 2026-08-24_
_Revisione architetturale 1.1 - 2026-08-25_
_Revisione architetturale 1.2 - 2026-08-26_
_Sessione condotta da: alessandro.giardina@intre.it con il team ARchetipo_
