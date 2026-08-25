# iMAGE Surfer - Product Requirements Document

**Autore:** ARchetipo
**Data:** 2026-08-25
**Versione:** 1.1

> **Revisione 1.1** — Revisione architetturale a seguito della valutazione esterna della sezione *Technical Architecture*. Modifiche sostanziali: durabilità e portabilità dei giudizi tramite sidecar XMP e identità del file separata dalla validità della cache (ADR-003, ADR-011, ADR-013); contratto esplicito di osservazione del filesystem (ADR-012); budget di memoria come vincolo primario dello scheduler (ADR-009); consenso progressivo ai permessi al posto dell'Accesso completo al disco obbligatorio (ADR-005). Lo scope dell'MVP non è stato ridotto: il costo aggiuntivo è dichiarato e accettato.

---

## Elevator Pitch

<!-- archetipo:prd section=elevator_pitch required=true -->

> Il Finder di macOS è un gestore di file che tollera le immagini. iMAGE Surfer è l'opposto: tratta una cartella come un rullino da lavorare, non come un elenco di file. Apri qualsiasi cartella, vedi solo le immagini, le giudichi grandi sullo schermo muovendoti con le sole frecce, leggi i metadati senza aprire nulla, e quando ti trovi davanti a otto scatti quasi identici l'app ti dice quali tenere e perché. Nessuna importazione, nessun catalogo, nessun lock-in: le tue foto restano dove sono, e i giudizi che dai restano con loro.
>
> Per **chi accumula migliaia di immagini in cartelle su macOS e le deve selezionare, rinominare e riorganizzare a mano**, che ha il problema di **usare un file manager generalista per un lavoro squisitamente visivo — anteprime minuscole, metadati sepolti in Get Info, navigazione che richiede il mouse e zero aiuto nella scelta tra scatti simili**, **iMAGE Surfer** è un **browser e banco di triage per immagini, nativo macOS** che **permette di vedere, giudicare e riorganizzare migliaia di foto senza mai lasciare la tastiera, con selezione assistita da AI che gira interamente in locale**. A differenza del **Finder (e dei cataloghi tipo Lightroom o Foto di macOS)**, il nostro prodotto **unisce la velocità di uno strumento professionale di triage all'assenza totale di importazione: la cartella sul disco resta l'unica fonte di verità, ogni giudizio resta leggibile anche fuori dall'app, e ogni operazione massiva è mostrata in anteprima e annullabile**.

---

## Vision

<!-- archetipo:prd section=vision required=true -->

Rendere il lavoro su un insieme di immagini — guardarle, sceglierle, scartarle, rinominarle, ordinarle — un'attività fluida, veloce e a tastiera, sfruttando fino in fondo ciò che macOS già offre: decodifica accelerata di ogni formato fotografico, visione artificiale sul Neural Engine, Cestino reversibile, notifiche del filesystem. Tutto in locale, senza cloud, senza account, senza spedire una sola immagine fuori dal Mac.

L'obiettivo di lungo periodo non è diventare un editor fotografico né un catalogo: è diventare **il livello di curation che manca tra il filesystem e gli strumenti di editing**. Il posto dove decidi *cosa merita di esistere* e *dove deve stare*, prima di aprire qualunque altra cosa.

### Differenziatore di Prodotto

Tre scelte, tenute insieme, che nessuna alternativa attuale combina:

1. **La cartella è la fonte di verità — fino in fondo.** L'app non importa, non sposta a tua insaputa, non crea una libreria proprietaria. L'indice locale è una cache di dati *ricalcolabili*, e cancellarlo non fa perdere nulla. Ma il principio vale anche al contrario: ciò che *tu* hai deciso — stelle, marcature — non è ricalcolabile, quindi non può vivere solo in una cache. Vive accanto all'immagine, in un sidecar standard che anche Bridge, Lightroom o darktable sanno leggere. Se domani disinstalli iMAGE Surfer, il tuo lavoro di selezione resta nella cartella. Questo è l'opposto esatto del modello Lightroom/Foto, dove il lavoro resta nel catalogo.
2. **Il triage a tastiera come interazione primaria, non come scorciatoia.** Frecce per muoversi, spazio per l'anteprima grande, un tasto per il rating, un tasto per marcare da scartare. Il mouse è opzionale, non necessario.
3. **L'AI argomenta, non decreta.** Il sistema non dice "questa è la più bella": raggruppa gli scatti quasi identici, li mette a confronto e mostra le ragioni misurabili di una proposta (nitidezza, volti rilevati, occhi aperti, esposizione, punteggio estetico). La decisione finale, e l'unico dito sul grilletto, restano dell'utente.

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
- Riorganizza le cartelle nel Finder senza pensarci: se uno strumento perde il suo lavoro perché lui ha spostato una cartella, quello strumento è fuori.

**Comportamenti e strumenti:**
Finder, Anteprima, QuickLook, occasionalmente un editor per un ritaglio. Lavora a tastiera dove può. Diffida delle scelte automatiche irreversibili, ma si fida di uno strumento che gli mostra prima cosa farà.

**Motivazioni:** Recuperare tempo su un lavoro ripetitivo che oggi lo frustra; avere un archivio di cui va fiero e di cui è padrone.
**Competenza tecnica:** Alta. Sa cosa sono EXIF, hash, spazio colore, sidecar. Non ha bisogno che gli si semplifichi la realtà, ha bisogno che gli si risparmino i clic.

#### Percorso Utente - Guidalberto

| Fase | Azione | Pensiero | Emozione | Opportunità |
|---|---|---|---|---|
| Consapevolezza | Dopo l'ennesima serata a scremare una cartella nel Finder, cerca "image browser macOS keyboard" | "Non può essere che nel 2026 io stia ancora aprendo e chiudendo file uno per uno" | Frustrazione, stanchezza | Comunicare il prodotto sulla frustrazione esatta, non su una lista di funzioni |
| Considerazione | Valuta Lightroom, Photo Mechanic, Foto di macOS | "Tutti vogliono importare le mie foto in una loro libreria. Io voglio solo *guardare* la mia cartella" | Diffidenza | Dichiarare in prima riga: nessuna importazione, la cartella resta la fonte di verità, i giudizi restano nella cartella |
| Primo utilizzo | Trascina una cartella con 800 foto sull'app | "Vediamo quanto ci mette prima di mostrarmi qualcosa. E vediamo cosa mi chiede di firmare" | Curiosità mista a scetticismo | Prima anteprima visibile in meno di un secondo; nessun account, nessun setup, nessun permesso chiesto prima del gesto che lo richiede |
| Uso regolare | Ogni scarico di schede finisce nell'app: triage a frecce, rating, gruppi di simili, rinomina massiva, smistamento in sottocartelle | "Quaranta minuti di lavoro diventati cinque" | Fiducia, controllo | Ricordare le cartelle recenti e i pattern di rinomina usati; rendere ogni operazione massiva annullabile |
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
- Non è a suo agio con strumenti da fotografo: se deve imparare un catalogo, torna al Finder.

**Comportamenti e strumenti:**
Finder, Anteprima, Canva, cartelle condivise. Usa il mouse più della tastiera, ma impara volentieri due o tre scorciatoie se le vede ripagate subito.

**Motivazioni:** Consegnare in tempo, senza errori evidenti, senza diventare un'esperta di software fotografico.
**Competenza tecnica:** Media. Sa cos'è un JPEG e cosa non è; di EXIF conosce la data e poco altro.

#### Percorso Utente - Adalgisa

| Fase | Azione | Pensiero | Emozione | Opportunità |
|---|---|---|---|---|
| Consapevolezza | Un collega le mostra l'app durante una consegna in ritardo | "Se mi dice davvero quale foto ha gli occhi aperti, mi cambia la giornata" | Speranza | Dimostrare il valore su un gruppo di raffica, che è il caso in cui il dolore è massimo |
| Considerazione | Teme che sia "uno strumento da fotografi" | "Non ho tempo di imparare Lightroom" | Timore di complessità | Nessuna importazione, nessuna configurazione: apri la cartella e sei operativa |
| Primo utilizzo | Seleziona 10 scatti simili e chiede "tieni le 3 migliori" | "Perché proprio queste tre?" | Sospetto | Mostrare sempre le motivazioni misurabili accanto alla proposta; nessuna cancellazione automatica |
| Uso regolare | Triage con rating, gruppi di simili, rinomina massiva su pattern aziendale, smistamento in sottocartelle per canale | "Ho un flusso, e lo ripeto identico ogni settimana" | Sollievo, competenza | Salvare i pattern e le regole ricorrenti come preset riutilizzabili (crescita) |
| Advocacy | Rimanda la cartella al fotografo e lui vede le stelle nel suo software | "Le consegne le facciamo così, e non devo più scrivere elenchi" | Orgoglio professionale | I giudizi in sidecar standard rendono la cartella autosufficiente anche fuori dall'app |

---

## Brainstorming Insights

<!-- archetipo:prd section=brainstorming_insights required=true -->

> Scoperte chiave e direzioni alternative esplorate durante la sessione di inception e durante la revisione architetturale successiva.

### Assunti Messi in Discussione

- **"Le cinque frustrazioni sono cinque funzioni da aggiungere."** Falso: sono un unico problema. Il Finder è un file manager che tollera le immagini. La conseguenza progettuale è che il cuore dell'app non è la griglia di anteprime, ma il **ciclo di triage** guarda → giudica → agisci → prossima, interamente a tastiera. Ogni funzione va valutata su quanto accorcia quel ciclo.
- **"Esiste un 'migliore' oggettivo che un modello può calcolare."** In gran parte falso, e il prodotto ne dipende. Su una raffica di scatti quasi identici "migliore" significa quasi sempre grandezze misurabili (a fuoco, non mosso, occhi aperti, esposizione sana) e solo di rado "più bello". Da qui la regola non negoziabile: **l'AI argomenta, non decreta**, e non cancella mai nulla da sola. Il punteggio estetico è ammesso come criterio, ma resta l'ultimo e il più debole, mostrato accanto agli altri e non al loro posto.
- **"L'AI è la funzione che vende, quindi va messa al centro."** Vera solo a metà. Il differenziatore commerciale è l'AI; il differenziatore d'uso quotidiano è la **latenza**. Un'app che scandisce 4.000 file calcolando embedding prima di mostrare la prima anteprima viene abbandonata al terzo utilizzo, quale che sia la qualità del modello. Conseguenza architetturale: analisi AI **solo su richiesta, solo su una selezione**, mai in scansione di cartella.
- **"Le frecce sono un dettaglio di comodità."** Falso: sono l'intero contratto di interazione. Se le frecce spostano la selezione, allora *tutto* il resto deve essere raggiungibile senza lasciare la tastiera, altrimenti la mano torna al mouse e il vantaggio svanisce. Questo vincola la mappa dei tasti a essere completa dal primo giorno, non arricchita in seguito.
- **"Bisogna scegliere un solo criterio di selezione."** Superato dal confronto: i criteri sono tre e sono **in cascata ordinata** — prima si raggruppano gli scatti quasi identici, poi dentro il gruppo si valuta il soggetto (volti, occhi aperti), infine la qualità tecnica fa da spareggio. Senza il primo passo, "le tre migliori di 40 foto" non è una domanda ben posta.
- **"L'indice locale è una cache buttabile."** Vero solo per metà, e la metà falsa era un difetto del documento. È cache tutto ciò che è **ricalcolabile** dai file: metadati, hash, feature print, anteprime. Non è cache ciò che l'utente ha **creato**: stelle e marcature non esistono da nessun'altra parte e non sono ricostruibili da nessuna sorgente. Metterli in una cache dichiarata sacrificabile è una contraddizione, e "avvisare l'utente in interfaccia" è una toppa, non una mitigazione. Conseguenza: i giudizi hanno un contratto di durabilità proprio, distinto da quello della cache (ADR-003, ADR-013).
- **"Rating e file restano associati finché il file non cambia."** Falso, e per una ragione che non era quella attesa. Spostare o rinominare un file nel Finder *sullo stesso volume conserva l'inode*: quel caso funzionava. A romperlo era la chiave scelta nel documento, `volume + inode + mtime + size`, che mescola **identità** ("a chi appartiene questo giudizio") e **validità** ("cosa devo ricalcolare"). Con quella chiave, un salvataggio atomico da un'altra app, un `touch`, una copia su volume esterno o una rimaterializzazione iCloud cancellano l'associazione anche se il contenuto non è cambiato di un byte. Conseguenza: le due chiavi vanno separate (ADR-011).
- **"Serve l'Accesso completo al disco."** Falso. Un'app **non in sandbox** non ne ha bisogno per aprire le cartelle scelte dall'utente: il FDA serve per ciò che TCC protegge in modo speciale (`~/Library`, dati di altre app, Mail, backup). Per aprire una cartella bastano il consenso per categoria che macOS chiede contestualmente e l'accesso concesso dal pannello di apertura o dal trascinamento. Chiedere il FDA all'avvio significa mettere un pedaggio non necessario davanti al primo valore percepito. Conseguenza: consenso progressivo, FDA opzionale (ADR-005).
- **"Limitare il parallelismo al numero di core protegge le risorse."** Falso per questo dominio. Il numero di core non dice nulla su quanta RAM occuperanno i prossimi lavori: un'immagine da 48 MP decodificata sono circa 190 MB, e otto in parallelo sono 1,5 GB di picco per un lavoro che dovrebbe costarne una frazione. La risorsa scarsa è la memoria, non la CPU. Conseguenza: il limite dello scheduler è un budget di memoria, e il parallelismo ne è derivato (ADR-009).

### Nuove Direzioni Scoperte

- **Anti-problem ("come rendiamo questa app inutilizzabile?").** Le risposte hanno prodotto i vincoli non funzionali più utili del documento: scansione bloccante all'apertura, coda di decodifica senza cancellazione allo scroll, cancellazioni irreversibili, ricalcolo dell'indice a ogni avvio. Ognuno di questi anti-pattern è diventato un requisito rovesciato. La revisione architetturale ne ha aggiunti due: **bruciare CPU a vuoto reagendo a ogni evento del filesystem**, e **crescere in memoria fino al crash silenzioso su cartelle grandi**.
- **"E se togliessimo l'AI?" (what if).** L'app resterebbe utile: filtro dei soli file immagine, anteprime grandi, navigazione a frecce e pannello metadati risolvono già quattro frustrazioni su cinque. Questo dà un ordine di implementazione robusto: **il triage a tastiera deve stare in piedi da solo**, e la parte AI si innesta sopra un'app già funzionante. Riduce drasticamente il rischio d'esecuzione.
- **Audience flip (dal proprietario del Mac al team).** Immaginando l'app in mano a un reparto marketing sono emerse due esigenze assenti nel brief originale ma naturali: **preset condivisibili** di rinomina e smistamento, e la distribuzione a terzi (che implica sandbox). Entrambe rinviate consapevolmente alla fase di crescita, ma l'architettura non deve precluderle: le regole vanno modellate come dati serializzabili, non come codice.
- **Il sidecar non è una difesa, è un'interfaccia.** Nato per proteggere i giudizi dalla perdita dell'indice, il sidecar XMP si è rivelato la prima funzione che fa **parlare iMAGE Surfer la lingua degli altri strumenti**: Adalgisa rimanda la cartella al fotografo e lui vede le stelle in Bridge senza che nessuno gli abbia mandato un elenco. È il differenziatore n°1 portato alle sue conseguenze: se la cartella è la fonte di verità, allora tutto ciò che conta deve stare nella cartella — compreso il lavoro di selezione.
- **Il journal delle operazioni come funzione, non come dettaglio tecnico.** Registrare ogni rinomina/spostamento massivo rende possibile un "annulla" che sopravvive alla chiusura dell'app. È ciò che trasforma un'operazione su 800 file da atto di fede in operazione normale — ed è quindi un elemento di fiducia, non solo di robustezza. Con i sidecar il journal si estende naturalmente: un lotto è invertibile solo se registra anche i file collegati che ha mosso.
- **Il pannello metadati come acceleratore di selezione.** Nato per risolvere la frustrazione 4, si è rivelato utile anche altrove: ISO alto e tempo di scatto lungo *predicono* rumore e mosso. Gli stessi metadati che l'utente legge alimentano l'ordinamento dei candidati.
- **L'hash che paga due volte.** L'hash del contenuto era stato introdotto solo per i duplicati esatti. Serve anche come **identità di riserva** quando l'inode cambia: riconosce lo stesso scatto dopo una copia, uno spostamento tra volumi o un salvataggio atomico di un'altra app. Costo marginale nullo, e risolve la maggioranza dei casi reali di "ho riorganizzato le cartelle nel Finder" senza scrivere un solo byte nella cartella dell'utente.
- **Il momento del permesso come momento di progetto.** Il consenso al filesystem non è un dettaglio di installazione: è l'unico istante in cui il sistema operativo si mette tra l'utente e le sue foto. Chiesto **dopo il gesto che lo motiva** (ha appena trascinato una cartella, e la vede sullo sfondo) è una conseguenza ovvia; chiesto su una schermata di benvenuto è un ostacolo. La differenza è interamente di progettazione dell'esperienza, non di tecnologia.

### Assunti da Validare

- **Soglia di similarità.** Il valore iniziale della distanza tra feature print per considerare due immagini "quasi duplicate" è una stima da calibrare su materiale reale. Il PRD fissa un default e impone che la soglia sia regolabile con feedback visivo immediato. *Domanda aperta: quale valore funziona su raffiche di smartphone rispetto a scatti di mirrorless?*
- **Utilità reale del punteggio estetico.** È stato incluso nell'MVP su scelta esplicita dell'utente. Resta da verificare che aggiunga informazione oltre ai criteri misurabili e che non venga percepito come arbitrario. *Se dopo l'uso reale non sposta le decisioni, va declassato a criterio opzionale disattivabile.*
- **Peso e provenienza del modello estetico.** Un modello open source di image-quality assessment convertito in Core ML incide sulle dimensioni del bundle. *Domanda aperta: bundle unico più grande, oppure download al primo utilizzo? La seconda strada introduce l'unica connessione di rete dell'app.*
- **Interoperabilità reale del sidecar.** L'MVP scrive `xmp:Rating` e un'etichetta secondo lo schema XMP Basic in un file `.xmp` affiancato. *Domande aperte: quale convenzione di nome adottare per massimizzare la compatibilità (`foto.jpg.xmp` oppure `foto.xmp`)? Come si comporta il nostro sidecar quando l'immagine ha già un sidecar scritto da un altro strumento con campi che non conosciamo — e la regola "conserva i campi non compresi e riscrivi solo i propri" regge su casi reali?* Da verificare su materiale prodotto da Bridge, Lightroom, darktable e digiKam.
- **Politica di conflitto sidecar ↔ indice.** L'MVP fa prevalere la fonte modificata più di recente e lo dichiara. *Da confermare sull'uso reale: è la regola che l'utente si aspetta, o preferisce essere interpellato quando le due fonti divergono?*
- **Volumi in sola lettura e sidecar.** Su una cartella non scrivibile (volume di rete in sola lettura, immagine disco montata, cartella condivisa senza permessi) il sidecar non può essere scritto. *Assunto per l'MVP: i giudizi restano nell'indice e l'interfaccia dichiara chiaramente che su questa cartella non sono portabili. Da confermare che sia comprensibile e non percepito come un errore.*
- **Ampiezza della finestra di quiete per gli eventi del filesystem.** Il valore iniziale è una stima. *Da calibrare: troppo corta e l'app reagisce a scritture ancora in corso, troppo lunga e l'aggiornamento della vista sembra lento durante uno scarico di schede.*
- **Valore del budget di memoria.** Il tetto iniziale e la stima del costo per immagine sono ipotesi da misurare su hardware reale, dal Mac con meno memoria in target fino alle configurazioni ampie. *Da validare con un test di lunga durata prima di considerare stabile lo scheduler.*
- **RAW rinviato alla crescita.** Assunto: il flusso di lavoro attuale è basato su JPEG/HEIC. *Se in pratica gli scatti importanti sono RAW, la priorità va rivista subito: il modello dei dati (coppia RAW+JPEG affiancata, anteprima incorporata, sidecar condiviso dalla coppia) non è un dettaglio da aggiungere dopo senza costi.*
- **Ricorsività delle operazioni massive.** Assunto per l'MVP: le operazioni agiscono sulla cartella corrente, non sull'albero sottostante. *Da confermare: la ricorsione moltiplica i modi in cui un'operazione massiva può fare danni.*
- **Nessuna integrazione con la libreria Foto di macOS.** Assunto: le immagini di interesse vivono in cartelle del filesystem. *Da confermare.*
- **Numero di "migliori" da tenere.** Il brief dice "2 o 3": modellato come parametro (default 3) e non come costante.
- **Tenuta dell'MVP allargato.** La revisione 1.1 ha aggiunto lavoro sostanziale (sidecar, identità doppia, riconciliazione del filesystem, budget di memoria) senza togliere nulla. *Assunto esplicito: il tempo di realizzazione si allunga e viene accettato. Da rivedere al primo incremento consegnato, con Area 12 — Editing di base come primo candidato al rinvio se la stima si rivelasse ottimistica.*

### Rischi Principali

- **Rischio di esecuzione — latenza percepita.** È il rischio primario. Se aprire una cartella da 3.000 immagini non è immediato, l'app perde contro il Finder a prescindere da tutto il resto. Mitigazione: anteprime dal servizio di sistema con cache su disco, decodifica solo di ciò che è visibile, cancellazione aggressiva della coda allo scroll, indice persistente per non ricalcolare mai due volte.
- **Rischio di adozione — sfiducia nell'AI.** Una proposta di selezione non spiegata viene disattivata dopo pochi utilizzi. Mitigazione: motivazioni sempre visibili, soglie regolabili, nessuna azione distruttiva automatica, l'utente conferma sempre.
- **Rischio di perdita dati sulle operazioni massive.** Rinominare o spostare centinaia di file è la funzione più utile e la più pericolosa. Mitigazione a tre livelli: anteprima obbligatoria prima dell'esecuzione, journal persistente con annullamento, eliminazioni sempre nel Cestino di macOS e mai `unlink`.
- **Rischio di perdita del lavoro di giudizio.** Distinto dal precedente: qui non si perdono file, si perdono ore di triage. Si materializza quando l'utente riorganizza le cartelle fuori dall'app, cambia Mac, o svuota l'indice. Mitigazione a due livelli: identità del file separata dalla validità della cache, con hash del contenuto come identità di riserva; e sidecar XMP accanto all'immagine, che rende il giudizio indipendente sia dall'indice sia dall'app.
- **Rischio tecnico — coerenza della cache.** Un indice che si disallinea dal filesystem produce anteprime sbagliate o file fantasma, il difetto che più rapidamente distrugge la fiducia. Mitigazione: identità e validità come chiavi distinte, riconciliazione per differenza al posto della fiducia negli eventi, indice sempre ricostruibile da zero.
- **Rischio tecnico — tempesta di eventi del filesystem.** L'infrastruttura di notifica di macOS è rumorosa, coalescente e a volte lacunosa: reagire ingenuamente a ogni evento produce un'app che consuma CPU a vuoto ogni volta che il sistema scrive un file temporaneo, e che può auto-innescarsi scrivendo i propri sidecar. Mitigazione: finestra di quiete con coalescenza per ambito, lista di esclusione che comprende le scritture dell'app stessa, riconciliazione come unica fonte di verità, gestione esplicita della perdita di eventi da parte del kernel.
- **Rischio tecnico — esaurimento silenzioso della memoria.** L'uso intensivo di decodifica e di modelli su cartelle grandi produce picchi che portano a un arresto senza messaggio, il difetto peggiore perché non lascia traccia e non viene cercato finché non colpisce un utente. Mitigazione: decodifica sempre ridimensionata e mai a piena risoluzione, blocchi di rilascio espliciti attorno a ogni elemento elaborato e non attorno al lotto, parallelismo derivato da un budget di memoria, reazione alla pressione di memoria del sistema, e un test di lunga durata in integrazione continua che fallisce se l'occupazione cresce in modo monotono.
- **Rischio di adozione — attrito dei permessi al primo avvio.** Il primo consenso al filesystem è il punto in cui si perde l'utente che non ha ancora visto nulla di valore. Mitigazione: nessun permesso richiesto prima del gesto che lo motiva, nessun Accesso completo al disco come prerequisito, motivazione scritta nel dialogo di sistema, e uno stato di rifiuto che spiega ed è recuperabile invece di essere una finestra vuota.
- **Rischio di scope — l'editing.** "Editing di base" è un imbuto che può ingoiare l'MVP. Mitigazione: l'MVP contiene solo trasformazioni geometriche (rotazione, capovolgimento, ritaglio). Regolazioni tonali ed editing non distruttivo sono esplicitamente fuori. È il primo candidato al rinvio se le stime dell'MVP allargato non reggono.
- **Rischio di scope — l'MVP è cresciuto.** La revisione architetturale ha aggiunto funzioni sostanziali senza toglierne, per scelta esplicita. Il rischio non è tecnico ma di consegna: un MVP che non arriva mai non è un MVP. Mitigazione: l'ordine di implementazione resta quello scoperto con il "what if" — prima il triage a tastiera in piedi da solo, poi la durabilità dei giudizi, poi l'AI — così che ogni tappa sia già utilizzabile.
- **Rischio operativo — assenza di sandbox.** La scelta di un'app personale non in sandbox limita la distribuzione a terzi. Accettato consapevolmente per l'MVP; la sandbox è una funzione di crescita e l'architettura non deve dare per scontato l'accesso illimitato al filesystem: ogni accesso passa da un livello unico, che è anche il punto d'innesto dei bookmark con ambito di sicurezza.

---

## Product Scope

<!-- archetipo:prd section=product_scope required=true -->

### MVP - Minimum Viable Product

Il criterio di taglio dell'MVP: **risolvere tutte e cinque le frustrazioni dichiarate, più le tre capacità richieste (a, b, c), sulla scala reale di 10.000-50.000 immagini, senza mai mettere a rischio i file né il lavoro di giudizio dell'utente**. Tutto ciò che non serve a questo è fuori.

**1. Apertura e navigazione delle cartelle**
- Apertura di una cartella qualsiasi tramite trascinamento, dialogo di sistema, cartelle recenti o preferiti nella barra laterale.
- **Solo le immagini sono visibili**: ogni altro tipo di file è escluso dalla vista (frustrazione 1). Contatore del contenuto non-immagine, senza mai mostrarlo mescolato.
- Ordinamento per nome, data di scatto, data di modifica, dimensione, rating.
- Nessun permesso richiesto prima del gesto che lo motiva: si apre una cartella e si lavora.

**2. Sincronizzazione con il filesystem**
- Aggiornamento automatico quando la cartella cambia sotto l'app, anche per opera di altre applicazioni.
- Gli eventi del sistema sono trattati come suggerimento: la verità è sempre una riconciliazione per differenza tra cartella e catalogo.
- Nessun consumo di risorse a cartella ferma; nessuna reazione ai file di servizio del sistema né alle scritture dell'app stessa.
- Le modifiche avvenute mentre l'app era chiusa sono rilevate alla riapertura, senza rifare tutto da capo.

**3. Visualizzazione a griglia e anteprima grande**
- Griglia di anteprime con dimensione della cella regolabile fino a molto grande (frustrazione 2), fluida su migliaia di elementi.
- Anteprima grande a pannello e a schermo intero, con zoom fino a 1:1 e panoramica.
- **Navigazione integralmente a frecce** in griglia e in anteprima grande, senza mai passare dal mouse (frustrazione 3); selezione multipla da tastiera.

**4. Metadati sempre a portata d'occhio**
- Pannello metadati permanente e commutabile con un tasto: dati file, dimensioni, EXIF (fotocamera, obiettivo, ISO, tempo, diaframma, focale, data/ora di scatto), IPTC, GPS, spazio colore (frustrazione 4).
- Il pannello segue la selezione senza latenza percepibile; per selezioni multiple mostra i valori comuni.

**5. Giudizio, marcatura e loro durabilità**
- Rating 1-5 stelle e marcatura "da scartare" da tastiera.
- Filtri per rating, per marcatura, per formato, per intervallo di date.
- **I giudizi sono scritti in un sidecar XMP accanto all'immagine**, in formato standard leggibile da altri strumenti fotografici, e non solo nell'indice locale. L'immagine originale non viene mai aperta in scrittura.
- **I giudizi sopravvivono agli spostamenti fatti fuori dall'app**: l'identità dell'immagine è indipendente dalla data di modifica e ricade sul contenuto quando il riferimento del filesystem cambia.

**6. Operazioni su file, singole e massive**
- Spostamento, copia, rinomina di singole immagini e di selezioni; i sidecar seguono sempre l'immagine.
- Eliminazione **sempre nel Cestino di macOS**, con annullamento.
- **Rinomina massiva guidata da pattern** su regole e metadati (capacità a), con anteprima obbligatoria `da → a`, politica esplicita per collisioni e metadati mancanti, e annullamento persistente.
- **Creazione massiva di sottocartelle e smistamento per regole** (capacità b): per data di scatto, fotocamera, formato, rating, marcatura; anteprima e annullamento con lo stesso contratto della rinomina.

**7. Duplicati**
- Rilevamento dei **duplicati esatti** per contenuto (byte-identici anche con nome diverso) e pannello di risoluzione che propone quale copia tenere.
- Rilevamento dei **gruppi di quasi-duplicati** (raffiche, scatti dello stesso momento) con soglia regolabile.

**8. Selezione assistita — "tieni le migliori N"** (capacità c, frustrazione 5)
Pipeline in cascata sull'ordine di priorità stabilito:
1. raggruppamento per similarità visiva e vicinanza temporale;
2. analisi del soggetto: volti rilevati, qualità del volto, occhi aperti/chiusi;
3. qualità tecnica misurabile: nitidezza sul soggetto, mosso, esposizione e clipping, rumore stimato;
4. punteggio estetico da modello open source locale, come criterio di spareggio finale.
- Proposta di N immagini da tenere (default 3, regolabile) **con le motivazioni sempre visibili** per ciascun candidato.
- Nessuna azione distruttiva automatica: l'utente conferma, e l'esito è comunque reversibile.
- Esecuzione **solo su richiesta e solo su una selezione**, mai come scansione di cartella.

**9. Editing di base**
- Rotazione di 90°, capovolgimento orizzontale e verticale, ritaglio con proporzioni libere e predefinite.
- Salvataggio come copia oppure sovrascrittura, con scelta esplicita e conservazione dei metadati.

**10. Fondamenta trasversali**
- Indice locale persistente come cache dei soli dati ricalcolabili: la cartella resta la fonte di verità e i giudizi vivono accanto alle immagini.
- Un unico livello di accesso al filesystem: l'unico punto del codice che può scrivere, spostare o eliminare qualcosa.
- Scheduler governato da un budget di memoria, con priorità alle celle visibili e cancellazione immediata del lavoro non più necessario.
- Mappa dei tasti completa e visibile in un pannello di aiuto.
- Accessibilità: etichette VoiceOver sui metadati e sui controlli, rispetto di *Riduci movimento* e *Aumenta contrasto*, area dei bersagli di clic dimensionata per l'uso reale, operabilità totale da tastiera.

### Growth Features (Post-MVP)

- **Supporto RAW** (CR2/CR3, NEF, ARW, DNG, ORF) con gestione delle coppie RAW+JPEG affiancate e sidecar condiviso dalla coppia.
- **Editing non distruttivo**: regolazioni tonali (esposizione, contrasto, saturazione, bilanciamento) con file affiancato e storico reversibile; l'originale non viene mai toccato.
- **Preset riutilizzabili e condivisibili** per pattern di rinomina e regole di smistamento.
- **Confronto affiancato** di 2-4 immagini con zoom sincronizzato — il modo naturale di risolvere un gruppo di quasi-duplicati.
- **Ricerca e filtri cross-cartella** sull'indice locale (per fotocamera, data, rating, formato).
- **Parole chiave e tag**: gestione delle keyword nel sidecar e, su richiesta esplicita e per lotti confermati, scrittura IPTC dentro i file.
- **Classificazione automatica per soggetto** (persone, animali, paesaggio, documento, schermata) usando la classificazione di sistema.
- **Esportazione** con ridimensionamento, conversione di formato e rimozione selettiva dei metadati sensibili (GPS).
- **Vista mappa** per le immagini geolocalizzate.
- **Distribuzione a terzi**: sandbox con cartelle autorizzate dall'utente, aggiornamenti automatici.
- **Operazioni ricorsive** sull'albero delle sottocartelle, con protezioni aggiuntive.

### Vision (Future)

- **Ricerca semantica in linguaggio naturale** sugli embedding già calcolati in locale ("il tramonto sul molo con la bici"), senza mai inviare nulla in rete.
- **Assistente di curation**: dall'insieme di un evento propone una selezione ragionata e una struttura di cartelle, spiegando ogni scelta.
- **Cartelle intelligenti** con regole persistenti che si applicano da sole al materiale nuovo.
- **Sincronizzazione dell'indice tra più Mac** (rating e giudizi seguono l'utente, le immagini restano dove sono).
- **Supporto video** con lo stesso modello di triage, estratto sui fotogrammi chiave.
- **Estendibilità**: regole e criteri di punteggio definibili dall'utente.

---

## Technical Architecture

<!-- archetipo:prd section=technical_architecture required=true -->

> **Proposta da:** Leonardo (Architect)

### System Architecture

Applicazione **nativa macOS, monoprocesso, interamente locale**: nessun server, nessuna rete a tempo di esecuzione (unica eccezione possibile, il download iniziale del modello estetico se non incluso nel bundle), nessun account.

Il vincolo "solo macOS" è sfruttato deliberatamente: le tre capacità più costose del prodotto — decodifica veloce di ogni formato fotografico, embedding di similarità visiva, rilevamento e valutazione dei volti — sono **già presenti nel sistema operativo**, accelerate su GPU e Neural Engine. Non vengono reimplementate né importate come dipendenze.

L'architettura riconosce **due nature di dato**, e le tratta in modo diverso perché hanno garanzie diverse:

- **Dato derivato** — metadati letti dai file, hash, feature print, anteprime, punteggi. È ricalcolabile dalla cartella in qualunque momento, quindi vive in una cache che può essere distrutta senza perdita.
- **Dato autorale** — stelle e marcature. Non esiste altrove e non è ricostruibile da nessuna sorgente. Vive **accanto all'immagine** in un sidecar standard, e l'indice ne tiene solo una copia rapida per filtrare e ordinare.

Il flusso dei dati è una pipeline a stadi, con l'indice locale come memoria dei risultati già calcolati e il sidecar come deposito durevole dei giudizi:

```text
Cartella su disco  ◀── osservatore FS ──┐
   │  (enumerazione + filtro per tipo    │  (eventi = suggerimento;
   │   immagine, via UTType)             │   verità = riconciliazione
   ▼                                     │   per differenza, con finestra
Catalogo in memoria                      │   di quiete ed esclusioni)
   │  identità:  volume+inode → hash     │
   │  validità:  mtime + size            │
   │                                     │
   ├──────────────┬──────────────────────┘
   │              │
   │              ▼
   │        Sidecar XMP accanto all'immagine  ◀── giudizi (fonte durevole)
   │              │  lettura all'indicizzazione / scrittura atomica
   │              ▼
   │        Indice SQLite (cache dei dati derivati + copia rapida dei giudizi)
   │              ▲
   │ (su richiesta, per celle visibili)  │
   ▼                                     │
Servizio anteprime  ─────────────────────┘
   │  QuickLook + cache su disco
   ▼
Griglia / Anteprima grande
   │
   │ (su richiesta, su una selezione)
   ▼
Pipeline di analisi
   raggruppamento → soggetto → qualità tecnica → estetica
   │        (sotto scheduler a budget di memoria)
   ▼
Proposta con motivazioni  →  conferma utente
   │
   ▼
Operazioni su file (immagine + sidecar collegato, sempre insieme)
   │  attraverso il livello unico di accesso
   │  (journal persistente + Cestino di macOS)
   ▼
Annullamento persistente
```

**Pattern Architetturale:** MVVM su SwiftUI con nucleo di dominio in pacchetti SPM indipendenti dalla UI; concorrenza strutturata con attori; pipeline a stadi con code delimitate, budget di memoria e cancellazione; separazione esplicita tra dato derivato (cache) e dato autorale (sidecar); ogni scrittura sul filesystem attraversa un livello unico.

**Componenti Principali:**

- **`Catalog`** — enumerazione della cartella, filtro per tipo immagine tramite `UTType`, **identità** (volume + inode, con hash del contenuto come identità di riserva) e **validità** (mtime + size) tenute come chiavi distinte, ordinamenti e filtri. Contiene l'**osservatore del filesystem** e il **riconciliatore**: l'osservatore raccoglie gli eventi, li smorza in una finestra di quiete e li coalesce per ambito; il riconciliatore rienumera l'ambito e produce una differenza rispetto al catalogo. Nessuna decisione è mai presa sull'evento in sé. Non conosce la UI.
- **`Metadata`** — lettura di EXIF/IPTC/GPS/TIFF e proprietà immagine tramite ImageIO (`CGImageSource`); normalizzazione in un modello tipizzato e stabile, tollerante ai metadati assenti.
- **`Sidecar`** — lettura e scrittura dei giudizi in file `.xmp` affiancati all'immagine: `xmp:Rating` e etichetta secondo lo schema XMP Basic. Scrittura **atomica** (file temporaneo sullo stesso volume + rinomina atomica) e **conservativa** (i campi scritti da altri strumenti che non conosciamo vengono riletti e riscritti invariati). Non apre mai in scrittura il file immagine. Conosce la politica di conflitto con l'indice e la rende esplicita al chiamante.
- **`Thumbnails`** — generazione anteprime tramite QuickLook Thumbnailing con cache su disco a due misure (griglia e anteprima grande); decodifica **sempre ridimensionata** via ImageIO (`CGImageSourceCreateThumbnailAtIndex` con dimensione massima dichiarata), mai il fotogramma a piena risoluzione; cache in memoria con limite di costo e svuotamento sulla pressione di memoria del sistema.
- **`Scheduler`** — punto unico di ammissione del lavoro asincrono. Limita il parallelismo in base a un **budget di memoria** e al costo stimato dei prossimi elementi (le dimensioni in pixel sono già nell'indice), non al numero di core; dà priorità alle celle visibili; cancella immediatamente il lavoro delle celle uscite dallo schermo; avvolge **ogni singolo elemento** in un blocco di rilascio esplicito, mai il lotto.
- **`Duplicates`** — duplicati esatti a tre stadi (dimensione → hash parziale di testa e coda → SHA-256 completo solo su collisione); quasi-duplicati per distanza tra feature print di Vision combinata alla vicinanza temporale EXIF, con clustering a soglia. L'hash prodotto qui è lo stesso usato da `Catalog` come identità di riserva.
- **`Quality`** — analisi del soggetto (rilevamento volti, qualità di cattura del volto, landmark oculari per occhi aperti/chiusi) e della qualità tecnica (nitidezza per varianza del Laplaciano calcolata **sul soggetto ritagliato** e non sull'intero fotogramma, istogramma per esposizione e clipping, stima del rumore) su immagine ridimensionata; punteggio estetico da modello Core ML come ultimo criterio. Restituisce sempre un punteggio **scomposto e spiegabile**, mai un numero unico.
- **`Access`** — livello unico di accesso al filesystem: l'unico punto del codice autorizzato a creare, scrivere, spostare o eliminare. Custodisce anche i bookmark delle cartelle recenti e preferite, la richiesta contestuale dei permessi e la diagnosi di un accesso negato. È il punto d'innesto della futura sandbox: introdurre i bookmark con ambito di sicurezza sarà una modifica confinata qui.
- **`FileOps`** — spostamento, copia, rinomina, eliminazione nel Cestino; motore di rinomina massiva basato su pattern; motore di smistamento in sottocartelle basato su regole. Ogni operazione tratta l'immagine e il suo sidecar come **una sola unità indivisibile**. **Anteprima obbligatoria (dry-run)** e **journal persistente delle operazioni** che rende annullabile un lotto, file collegati compresi, anche dopo il riavvio dell'app. Scrive esclusivamente attraverso `Access`.
- **`IndexStore`** — schema e accesso a SQLite: metadati, hash, feature print, copia rapida dei giudizi, journal delle operazioni. Chiavi di identità e di validità modellate come colonne distinte. Ricostruibile da zero per progetto: dopo uno svuotamento, i giudizi rientrano dai sidecar.
- **`UI`** — SwiftUI per la struttura, la barra laterale, i pannelli e i dialoghi; ponte AppKit su `NSCollectionView` per la griglia, che su decine di migliaia di celle regge dove una griglia SwiftUI pura non arriva. Mappa dei tasti centralizzata in un unico punto, non sparsa nelle viste.

### Technology Stack

| Livello | Tecnologia | Versione | Motivazione |
|---|---|---|---|
| Linguaggio | Swift | 6.x (concorrenza stretta) | Unico linguaggio di prima classe per le API di sistema che costituiscono il valore dell'app; la concorrenza strutturata è esattamente il modello richiesto dalle pipeline con cancellazione |
| Piattaforma applicativa | AppKit + Swift Concurrency | macOS 15+ | Il target è una sola piattaforma; nessun livello di astrazione multipiattaforma da mantenere |
| Framework di interfaccia | SwiftUI, con ponte AppKit (`NSCollectionView`) per la griglia | macOS 15+ | SwiftUI per velocità di costruzione di pannelli e dialoghi; `NSCollectionView` dove serve riuso di celle e fluidità su decine di migliaia di elementi |
| Anteprime e decodifica | QuickLook Thumbnailing + ImageIO + Core Image | di sistema | Supporto nativo di HEIC, TIFF, WebP e (in prospettiva) RAW senza dipendenze; decodifica ridimensionata e trasformazioni accelerate |
| Osservazione del filesystem | File System Events con eventi a granularità di file e identificatore d'evento persistito | di sistema | Rilevare le modifiche senza polling e riprendere dopo la chiusura dell'app da dove si era rimasti; la granularità di file riduce l'ambito da riconciliare |
| Visione artificiale | Vision (feature print immagine, rilevamento e qualità volti, landmark) | di sistema | Embedding di similarità e valutazione volti sul Neural Engine: ordini di grandezza più rapidi di qualunque equivalente importato |
| Modello estetico | Modello open source di image-quality assessment convertito in Core ML | Core ML di sistema | Aggiunge il criterio di gradimento richiesto; eseguito **solo su gruppi già formati e solo su richiesta**, quindi con costo invisibile nel flusso normale |
| Giudizi portabili | Sidecar XMP (`xmp:Rating`, etichetta) come XML affiancato | XMP Basic | Formato standard già letto da Bridge, Lightroom, darktable, digiKam; è XML puro, quindi non introduce nessuna dipendenza esterna e non richiede di riscrivere il file immagine |
| Database | SQLite | 3 (di sistema) | Indice locale a file unico, senza processi da gestire; adeguato con margine a 10-50k immagini |
| Accesso ai dati | GRDB.swift | 7.x | Accesso SQLite tipizzato e testabile in Swift, con migrazioni versionate e osservazione delle modifiche |
| Autenticazione | Nessuna | — | App locale monoutente, senza account e senza servizi remoti |
| Test | Swift Testing (unità e integrazione) + XCUITest (percorsi critici a tastiera) | di sistema | I moduli SPM sono testabili senza avviare l'interfaccia; XCUITest copre la navigazione a tastiera, che è il contratto d'uso primario |
| Test di tenuta | Test di lunga durata su cartella di grandi dimensioni, eseguito in integrazione continua | — | La crescita di memoria e la reazione alle raffiche di eventi non emergono in un test unitario: servono sessioni lunghe con soglie di fallimento dichiarate |

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
│   ├── Catalog/                  # enumerazione, filtro tipi, identità/validità, osservatore + riconciliatore FS
│   ├── Metadata/                 # ImageIO -> modello metadati tipizzato
│   ├── Sidecar/                  # lettura/scrittura XMP affiancato, atomica e conservativa
│   ├── Thumbnails/               # QuickLook + cache su disco + decodifica sempre ridimensionata
│   ├── Scheduler/                # ammissione del lavoro, budget di memoria, priorità, cancellazione
│   ├── Duplicates/               # hash esatti + clustering quasi-duplicati
│   ├── Quality/                  # Vision, Core Image, Core ML: punteggi scomposti
│   ├── Access/                   # livello unico di accesso al filesystem, bookmark, permessi
│   ├── FileOps/                  # rinomina/smistamento massivi, dry-run, journal, Cestino, sidecar collegati
│   ├── IndexStore/               # schema SQLite, migrazioni, accesso (GRDB)
│   └── DesignSystem/             # componenti condivisi, tipografia, accessibilità
├── Tests/                        # test di integrazione trasversali + fixture immagini
│   ├── Fixtures/                 # raffiche, duplicati, EXIF mancanti, HEIC, orientamenti, sidecar di terzi
│   └── Soak/                     # test di lunga durata: memoria e raffiche di eventi FS
├── Scripts/
│   ├── build-dmg.sh              # pacchettizzazione e notarizzazione
│   └── lint.sh
├── docs/                         # PRD, wiki, mockup
└── .github/workflows/ci.yml
```

### Development Environment

Ambiente completamente locale, senza servizi da avviare: si apre il progetto Xcode e si esegue. Nessun contenitore, nessun database esterno, nessuna variabile d'ambiente obbligatoria.

**Permessi:** l'app **non richiede l'Accesso completo al disco** per funzionare. Al primo utilizzo di una cartella in Scrivania, Documenti, Download, su volume rimovibile o di rete, macOS mostra il proprio dialogo di consenso con la motivazione dichiarata nel bundle; le cartelle aperte dal pannello di sistema o trascinate sull'app sono accessibili senza ulteriori richieste. L'Accesso completo al disco resta un'opzione offerta a chi lavora su percorsi insoliti e non vuole più vedere dialoghi, mai un prerequisito. In sviluppo, le compilazioni successive possono invalidare il consenso già concesso: è un fastidio noto della fase di sviluppo e non riguarda l'app distribuita.

Le fixture di test (raffiche reali, duplicati esatti, immagini senza EXIF, HEIC, orientamenti EXIF non standard, sidecar XMP prodotti da strumenti di terze parti) sono versionate nel repository: sono la difesa contro i casi limite che si scoprono altrimenti solo in uso.

**Strumenti richiesti:** macOS 15 o successivo su Apple Silicon; Xcode 16 o successivo (Swift 6); `swift-format` e SwiftLint per lo stile; `xcodebuild` per build e test da riga di comando; `notarytool` e `create-dmg` per la distribuzione; Python con `coremltools` **solo** in fase di conversione del modello estetico, mai a tempo di esecuzione.

### CI/CD & Deployment

**Strumento di build:** `xcodebuild` (SPM per la risoluzione delle dipendenze dei pacchetti locali e di GRDB).

**Pipeline:** GitHub Actions su runner macOS. Ad ogni push: `swift-format --lint` e SwiftLint → build dei pacchetti SPM → test unitari di tutti i pacchetti → build del target applicativo → test XCUITest sui percorsi critici a tastiera. Su ramo principale e prima di ogni rilascio, in aggiunta: **test di lunga durata** su una cartella generata di grandi dimensioni, con soglie di fallimento dichiarate su occupazione di memoria di picco, crescita dell'occupazione nel tempo e numero di riconciliazioni prodotte da una raffica sintetica di eventi del filesystem. Su tag di versione: build in configurazione Release con hardened runtime, firma, notarizzazione, creazione del `.dmg` e pubblicazione come artefatto della release.

**Deployment:** distribuzione **manuale come `.dmg` notarizzato**, non in sandbox, secondo la scelta "app personale". Nessun canale di aggiornamento automatico nell'MVP (rinviato alla crescita insieme alla distribuzione a terzi).

**Infrastruttura di destinazione:** il Mac dell'utente. Nessuna infrastruttura server, nessun servizio remoto, nessuna telemetria.

### Architecture Decision Records (ADR)

- **ADR-001 — App nativa Swift/SwiftUI, non Electron o multipiattaforma.** *Decisione:* nativa. *Motivo:* le tre capacità portanti (decodifica di ogni formato fotografico, embedding di similarità, valutazione volti) sono servizi di sistema accelerati su hardware; in un runtime web andrebbero reimportate come dipendenze pesanti e girerebbero drasticamente più lente, colpendo esattamente il rischio primario del prodotto. *Conseguenza:* il codice non è portabile fuori da macOS — accettato come vincolo dichiarato del prodotto, non come limite.
- **ADR-002 — Anteprime da QuickLook Thumbnailing, non decodifica propria.** *Decisione:* il servizio di sistema è la sorgente primaria delle anteprime, con ImageIO come riserva e per lo zoom 1:1. *Motivo:* copertura gratuita dei formati (HEIC, TIFF, WebP, e RAW quando arriverà) e riuso della cache di sistema. *Conseguenza:* si dipende da una qualità di anteprima non controllata nel dettaglio; accettabile per la griglia, non per lo zoom, dove si decodifica direttamente — sempre a dimensione dichiarata, mai a piena risoluzione.
- **ADR-003 — La cache è buttabile; i giudizi dell'utente non sono cache.** *Decisione:* l'indice SQLite contiene due categorie di dato con garanzie diverse. È **cache** ciò che è ricalcolabile dai file (metadati, hash, feature print, anteprime, punteggi): cancellarlo non perde nulla. **Non è cache** ciò che l'utente ha creato (stelle, marcature): non esiste altrove, quindi ha una sede durevole propria accanto all'immagine (ADR-013) e nell'indice ne resta solo una copia rapida per filtrare e ordinare. *Motivo:* la versione precedente di questa decisione dichiarava buttabile anche il lavoro di giudizio e mitigava il rischio con un avviso in interfaccia. Un avviso non è una mitigazione: gli utenti riorganizzano le cartelle e si aspettano che il lavoro li segua. *Conseguenza:* l'indice resta integralmente ricostruibile — e dopo uno svuotamento i giudizi rientrano dai sidecar invece di sparire. La cartella è la fonte di verità anche per ciò che l'utente ha deciso, non solo per i pixel.
- **ADR-004 — Quasi-duplicati tramite feature print di Vision, non hash percettivo artigianale.** *Decisione:* distanza tra embedding di sistema, combinata alla vicinanza temporale EXIF. *Motivo:* qualità molto superiore a un hash percettivo su ritagli, esposizioni e piccoli movimenti, con costo computazionale sul Neural Engine. *Conseguenza:* la soglia non ha un significato assoluto e va calibrata: deve essere regolabile con anteprima visiva immediata dei gruppi.
- **ADR-005 — Consenso progressivo ai permessi; nessun Accesso completo al disco obbligatorio.** *Decisione:* `.dmg` notarizzato con hardened runtime, senza App Sandbox. L'app **non richiede** l'Accesso completo al disco: si affida al consenso per categoria che macOS chiede contestualmente alla prima apertura (Scrivania, Documenti, Download, volumi rimovibili e di rete) e all'accesso concesso dal pannello di apertura o dal trascinamento. Il FDA è offerto come opzione a chi vuole eliminare i dialoghi, mai come prerequisito. *Motivo:* la versione precedente di questa decisione chiedeva all'utente il permesso più ampio del sistema prima che avesse visto una sola immagine — e per una capacità che non ne ha bisogno: un'app fuori sandbox accede alle cartelle scelte dall'utente senza FDA, che serve solo per ciò che TCC protegge in modo speciale. Il costo era interamente di adozione, il beneficio nullo. *Conseguenza:* nessun permesso viene chiesto prima del gesto che lo motiva; un accesso negato produce uno stato spiegato e recuperabile e non una finestra vuota; tutte le richieste, i bookmark e la diagnosi vivono nel componente `Access`, che resta il punto d'innesto della futura sandbox. La distribuzione a terzi e il Mac App Store restano fuori portata fino all'introduzione della sandbox.
- **ADR-006 — Il modello estetico gira solo su richiesta, e solo dentro un gruppo già formato.** *Decisione:* mai in scansione di cartella; ingresso della pipeline già ridotto a pochi candidati. *Motivo:* protegge il vincolo di latenza, che è il rischio primario. *Conseguenza:* il punteggio estetico non è disponibile come criterio di ordinamento globale, e non lo sarà finché non esistono prove di prestazione che lo permettano.
- **ADR-007 — Reversibilità per costruzione: dry-run, journal, Cestino.** *Decisione:* nessuna operazione massiva viene eseguita senza anteprima; ogni lotto è registrato in un journal persistente; le eliminazioni passano dal Cestino di macOS. *Motivo:* la funzione più utile è anche la più pericolosa, e la fiducia è un requisito di prodotto. *Conseguenza:* il journal è parte dello schema SQLite dal primo giorno e ogni operazione di `FileOps` deve essere modellata come lotto descrivibile e invertibile, **file collegati compresi**: un lotto che ha mosso 800 immagini e 800 sidecar è invertibile solo se ha registrato entrambi.
- **ADR-008 — `NSCollectionView` per la griglia, SwiftUI per tutto il resto.** *Decisione:* ponte AppKit limitato alla griglia. *Motivo:* riuso di celle e fluidità su decine di migliaia di elementi. *Conseguenza:* una superficie di codice AppKit da mantenere, confinata a un solo componente con contratto esplicito verso il resto.
- **ADR-009 — Scheduler a budget di memoria, con cancellazione obbligatoria.** *Decisione:* ogni lavoro asincrono (anteprime, metadati, hash, Vision, Core ML) passa da uno scheduler unico che ammette lavoro fino a un **budget di memoria dichiarato**, stimando il costo dei prossimi elementi dalle dimensioni in pixel già note; dà priorità alle celle visibili; cancella immediatamente il lavoro di ciò che esce dallo schermo; avvolge **ogni singolo elemento** in un blocco di rilascio esplicito, mai il lotto; e riduce il budget quando il sistema segnala pressione di memoria. La decodifica è sempre a dimensione dichiarata, mai a piena risoluzione. *Motivo:* limitare il parallelismo al numero di core protegge la CPU e non la memoria, che in questo dominio è la risorsa scarsa: con immagini ad alta risoluzione il picco per elemento si misura in centinaia di megabyte, e in un gruppo di task concorrenti gli oggetti temporanei non vengono rilasciati finché il gruppo non termina. L'esito è l'arresto silenzioso per esaurimento memoria, che nessuno cerca finché non colpisce un utente. *Conseguenza:* nessun componente ha licenza di avviare lavoro "al volo" fuori dallo scheduler; il budget e la stima per elemento sono parametri misurati, non costanti scelte a intuito; e il test di lunga durata in integrazione continua è parte del contratto, non un extra.
- **ADR-010 — Le regole sono dati, non codice.** *Decisione:* pattern di rinomina e regole di smistamento sono modellati come strutture serializzabili con una grammatica dichiarata. *Motivo:* rende possibili preset, condivisione e cartelle intelligenti in seguito senza riscrivere il motore. *Conseguenza:* la grammatica dei token va specificata e versionata (vedi requisiti funzionali FR-026/FR-032).
- **ADR-011 — Identità del file separata dalla validità della cache.** *Decisione:* due chiavi distinte. **Identità** — a quale immagine appartiene un giudizio — è `volume + inode`, con l'**hash del contenuto come identità di riserva** quando il riferimento del filesystem cambia. **Validità** — cosa va ricalcolato — è `mtime + size`. La scadenza della validità invalida i dati derivati e **non tocca mai i giudizi**. *Motivo:* la chiave unica `volume + inode + mtime + size` della versione precedente mescolava le due nozioni, e qualunque tocco al file (salvataggio atomico di un'altra app, `touch`, copia su volume esterno, rimaterializzazione iCloud) cancellava l'associazione con il giudizio anche a contenuto immutato. L'hash è già calcolato per il rilevamento dei duplicati esatti: usarlo come identità di riserva ha costo marginale nullo e recupera la maggior parte dei casi reali di riorganizzazione fatta nel Finder. *Conseguenza:* lo schema dell'indice modella le due chiavi come colonne distinte con indici propri; la riconciliazione ricerca prima per inode e poi per hash prima di dichiarare una immagine sconosciuta.
- **ADR-012 — Gli eventi del filesystem sono un suggerimento; la verità è la riconciliazione.** *Decisione:* l'osservatore non aggiorna mai il catalogo a partire dal contenuto di un evento. Raccoglie gli eventi, li smorza in una **finestra di quiete**, li **coalesce per ambito**, e attiva un **riconciliatore** che rienumera quell'ambito e ne calcola la differenza rispetto al catalogo. Sono esclusi a priori i file di servizio del sistema, i file temporanei e di trasferimento incompleto, i file nascosti e **le scritture prodotte dall'app stessa**. Quando il kernel segnala di aver perso eventi si riconcilia l'intero ambito segnalato senza perdere né la selezione né i giudizi. L'identificatore dell'ultimo evento elaborato è persistito, così che alla riapertura si riprenda da lì invece di rifare tutto o di non accorgersi di nulla. *Motivo:* l'infrastruttura di notifica di macOS è rumorosa, coalescente e deliberatamente lacunosa sotto carico. Un'app che reagisce evento per evento consuma CPU a vuoto, mostra stati intermedi di file ancora in scrittura, e — scrivendo i propri sidecar — si auto-innesca in un ciclo di retroazione. *Conseguenza:* il costo di una raffica è limitato superiormente a una riconciliazione per finestra di quiete; l'ampiezza della finestra e la lista di esclusione sono parametri dichiarati e verificati da test di raffica sintetica; e la correttezza della vista non dipende mai dalla completezza degli eventi.
- **ADR-013 — I giudizi in sidecar XMP affiancato, mai dentro il file immagine.** *Decisione:* stelle ed etichette sono scritte in un file `.xmp` accanto all'immagine, in formato standard (`xmp:Rating` e etichetta secondo lo schema XMP Basic). La scrittura è **atomica** (file temporaneo sullo stesso volume e rinomina atomica) e **conservativa** (i campi presenti che non conosciamo vengono riletti e riscritti invariati). Il file immagine non viene **mai** aperto in scrittura per registrare un giudizio. La scrittura del sidecar è disattivabile; su cartelle non scrivibili si degrada all'indice, dichiarandolo. *Motivo:* i giudizi devono sopravvivere alla perdita dell'indice, al cambio di Mac e alla disinstallazione dell'app — e devono essere leggibili dagli strumenti che l'utente già usa, il che li rende una funzione e non solo un backup. La via alternativa, scrivere IPTC/XMP dentro il file, dà la stessa portabilità ma richiede di riscrivere immagini che l'utente non ha incluso in nessuna operazione: viola frontalmente NFR-A4 e con essa metà della promessa del prodotto. *Conseguenza:* ogni operazione di `FileOps` tratta immagine e sidecar come un'unica unità indivisibile, e il journal registra entrambi; la cartella contiene file in più, che sono esclusi dalla vista e contati a parte come file collegati; serve una politica di conflitto dichiarata quando sidecar e indice divergono; la scrittura del sidecar deve essere esclusa dall'osservatore del filesystem per non innescare una riconciliazione a ogni stella assegnata.

---

## Functional Requirements

<!-- archetipo:prd section=functional_requirements required=true -->

### Area 1 - Apertura e navigazione delle cartelle

- **FR-001** L'utente può aprire una cartella trascinandola sull'app o sulla sua icona, tramite il dialogo di apertura di sistema, dalle cartelle recenti o dai preferiti nella barra laterale.
- **FR-002** La vista mostra **esclusivamente** i file riconosciuti come immagini secondo il tipo di sistema (`UTType`), non secondo l'estensione. Nessun altro tipo di file è visibile in griglia.
- **FR-003** L'app indica quanti elementi non-immagine sono presenti nella cartella, senza mescolarli mai al contenuto visibile, distinguendo i **file collegati** (sidecar delle immagini presenti) dal resto del contenuto estraneo.
- **FR-004** L'utente può ordinare per nome, data di scatto, data di modifica, dimensione file e rating, in ordine crescente o decrescente, e l'ordinamento scelto persiste tra le sessioni.
- **FR-005** L'app ricorda le cartelle aperte di recente e permette all'utente di fissare cartelle preferite nella barra laterale; i riferimenti sono persistiti in modo da restare validi anche se la cartella viene rinominata o spostata sullo stesso volume.

### Area 2 - Osservazione della cartella e sincronizzazione

- **FR-006** L'app rileva le modifiche alla cartella aperta (file aggiunti, rimossi, rinominati, modificati da altre applicazioni) e aggiorna la vista senza intervento dell'utente, **senza perdere la selezione corrente** né la posizione di scorrimento.
- **FR-007** Gli eventi del filesystem non aggiornano mai direttamente il catalogo: attivano una **riconciliazione** che rienumera l'ambito interessato e ne calcola la differenza rispetto allo stato conosciuto. La vista riflette sempre il risultato della riconciliazione, mai il contenuto grezzo di un evento.
- **FR-008** Gli eventi sono smorzati in una **finestra di quiete** e coalescenti per ambito: una raffica di modifiche entro la finestra produce **una sola** riconciliazione. Un file ancora in scrittura (scaricamento, copia in corso) è considerato solo quando dimensione e data di modifica si sono stabilizzate.
- **FR-009** L'app ignora i file di servizio del sistema (`.DS_Store`, risorse `._*`), i file temporanei e di trasferimento incompleto, i file nascosti e **le scritture prodotte dall'app stessa** (in particolare i sidecar che ha appena salvato), così che nessuna di queste provochi un aggiornamento della vista o un consumo di risorse.
- **FR-010** Quando il sistema segnala di aver perso eventi sotto carico, l'app riconcilia integralmente l'ambito segnalato senza perdere la selezione, i giudizi né i risultati di analisi già calcolati.
- **FR-011** Le modifiche avvenute mentre l'app era chiusa sono rilevate alla riapertura riprendendo il flusso di eventi dall'ultimo punto elaborato, integrato da una riconciliazione della cartella aperta; l'utente non deve mai svuotare l'indice per vedere la cartella aggiornata.
- **FR-012** L'osservazione è attiva sulla sola cartella aperta e non discende ricorsivamente nelle sottocartelle; è sospesa quando nessuna cartella è aperta.

### Area 3 - Visualizzazione

- **FR-013** La griglia mostra le anteprime con dimensione della cella regolabile su almeno cinque livelli, fino a una dimensione che permetta di valutare la nitidezza senza aprire l'immagine.
- **FR-014** La griglia resta fluida durante lo scorrimento su cartelle di almeno 10.000 immagini, caricando le anteprime delle sole celle visibili e annullando il lavoro non più necessario.
- **FR-015** L'utente può aprire un'anteprima grande dell'immagine selezionata, a pannello o a schermo intero, con un solo tasto.
- **FR-016** Nell'anteprima grande l'utente può ingrandire fino alla scala 1:1 dei pixel e spostarsi nell'immagine, per valutare fuoco e dettaglio.
- **FR-017** Le immagini sono visualizzate rispettando l'orientamento EXIF e il profilo colore incorporato.
- **FR-018** L'app segnala visivamente le immagini per le quali non è possibile generare un'anteprima o leggere il contenuto, senza interrompere il caricamento delle altre.

### Area 4 - Navigazione da tastiera

- **FR-019** L'utente può spostare la selezione tra le immagini con i soli tasti freccia, sia in griglia (movimento bidimensionale) sia in anteprima grande (immagine precedente e successiva).
- **FR-020** L'utente può estendere la selezione da tastiera (freccia con modificatore), selezionare tutto e invertire la selezione.
- **FR-021** Tutte le azioni dell'MVP — anteprima grande, pannello metadati, rating, marcatura, spostamento nel Cestino, rinomina, avvio dell'analisi di selezione — sono attivabili da tastiera senza usare il mouse.
- **FR-022** L'app espone un pannello di aiuto che elenca tutte le scorciatoie attive, richiamabile con un tasto.

### Area 5 - Metadati

- **FR-023** Un pannello metadati, mostrabile e nascondibile con un tasto, presenta per l'immagine selezionata: nome e percorso, dimensione del file, dimensioni in pixel, formato, data di creazione e di modifica, spazio colore.
- **FR-024** Lo stesso pannello mostra i dati EXIF disponibili — fotocamera, obiettivo, ISO, tempo di esposizione, diaframma, lunghezza focale, data e ora di scatto, orientamento — e i dati IPTC e GPS quando presenti, indicando esplicitamente i campi assenti anziché ometterli silenziosamente.
- **FR-025** Il pannello si aggiorna al cambio di selezione senza latenza percepibile; con selezione multipla mostra i valori comuni e segnala i campi divergenti. L'utente può copiare il valore di un singolo campo o l'intero blocco di metadati.

### Area 6 - Rinomina massiva (capacità a)

- **FR-026** L'utente può rinominare una selezione di immagini applicando un pattern composto da testo libero e token. I token supportati nell'MVP sono almeno:

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

- **FR-027** L'app mostra **obbligatoriamente** un'anteprima `nome attuale → nome nuovo` per ogni file coinvolto prima di eseguire qualsiasi rinomina, evidenziando collisioni, caratteri non ammessi dal filesystem, nomi troppo lunghi e ricadute su dati mancanti.
- **FR-028** L'utente sceglie esplicitamente la politica per le collisioni: aggiungere un suffisso progressivo, saltare il file, oppure annullare l'intero lotto. Il valore predefinito non sovrascrive mai un file esistente.
- **FR-029** L'estensione originale del file è preservata e non è modificabile dal pattern.
- **FR-030** Ogni lotto di rinomina è registrato in un journal persistente e può essere annullato integralmente anche dopo la chiusura e riapertura dell'app, purché i file coinvolti non siano stati modificati nel frattempo; in caso di modifiche l'annullamento è parziale e l'app riporta esattamente cosa non ha potuto ripristinare.

### Area 7 - Smistamento in sottocartelle (capacità b)

- **FR-031** L'utente può generare automaticamente sottocartelle e spostarvi le immagini secondo una regola scelta tra: data di scatto (con granularità anno, anno-mese, anno-mese-giorno), fotocamera, formato del file, rating, marcatura da scartare.
- **FR-032** Il nome delle sottocartelle generate è definibile con la stessa grammatica di token della rinomina massiva.
- **FR-033** L'app mostra obbligatoriamente l'anteprima dell'albero risultante — quali cartelle verranno create e quanti file finiranno in ciascuna — prima di eseguire qualsiasi spostamento.
- **FR-034** Le immagini per le quali la regola non è applicabile (dato mancante) finiscono in una cartella di raccolta con nome configurabile, e non vengono mai lasciate in uno stato indeterminato.
- **FR-035** Anche lo smistamento è registrato nel journal e annullabile con lo stesso contratto della rinomina (FR-030).
- **FR-036** Nell'MVP le operazioni massive agiscono sulla cartella corrente e non discendono ricorsivamente nelle sottocartelle; questo limite è dichiarato in interfaccia.

### Area 8 - Giudizio, marcatura e filtri

- **FR-037** L'utente può assegnare un rating da 1 a 5 stelle, rimuoverlo, e marcare o smarcare un'immagine come "da scartare", con un singolo tasto e senza lasciare la posizione corrente.
- **FR-038** L'assegnazione di un giudizio è immediata nell'interfaccia e non attende il completamento della scrittura su disco; un'eventuale scrittura fallita è segnalata in modo visibile e non silenziosa, e riprovabile.
- **FR-039** L'utente può filtrare la vista per rating (minimo, esatto), per marcatura, per formato e per intervallo di date, e combinare i filtri.

### Area 9 - Durabilità e portabilità dei giudizi

- **FR-040** Rating e marcature sono scritti in un **sidecar XMP** affiancato all'immagine, in un formato standard leggibile dai principali strumenti fotografici, oltre a essere mantenuti nell'indice locale per filtrare e ordinare rapidamente.
- **FR-041** L'app **non apre mai in scrittura il file immagine** per registrare un giudizio. La scrittura del sidecar è atomica: un'interruzione o un arresto anomalo non può produrre un sidecar parziale né alterare l'immagine.
- **FR-042** Alla lettura, l'app riconosce i sidecar già presenti nella cartella, compresi quelli prodotti da altri strumenti, e ne importa rating ed etichetta. I campi che non conosce sono **conservati invariati** quando riscrive il file.
- **FR-043** Quando sidecar e indice divergono per la stessa immagine, l'app applica una politica di risoluzione dichiarata — prevale la fonte modificata più di recente — e rende la scelta visibile all'utente invece di applicarla in silenzio.
- **FR-044** Ogni operazione su file (spostamento, copia, rinomina, eliminazione, smistamento) tratta l'immagine e il suo sidecar come **una sola unità**: il sidecar segue sempre l'immagine, è incluso nell'anteprima dell'operazione, è registrato nel journal ed è ripristinato dall'annullamento.
- **FR-045** I giudizi restano associati all'immagine anche quando questa viene spostata, copiata o modificata **al di fuori dell'app**: l'app riconosce l'immagine per riferimento del filesystem e, quando questo non basta, per contenuto.
- **FR-046** La scrittura dei sidecar è disattivabile dalle impostazioni. Quando la cartella non è scrivibile, i giudizi restano nell'indice e l'app dichiara chiaramente che su quella cartella non sono portabili, senza presentarlo come un errore.
- **FR-047** L'interfaccia dichiara in modo comprensibile dove vivono i giudizi e cosa comporta svuotare l'indice o disattivare i sidecar, così che l'utente possa scegliere con cognizione.

### Area 10 - Duplicati

- **FR-048** L'app individua i **duplicati esatti** (contenuto byte-identico, anche con nome diverso) all'interno della selezione o della cartella corrente, procedendo per stadi di costo crescente e senza leggere integralmente file che possono essere esclusi prima.
- **FR-049** I duplicati esatti sono presentati in gruppi con un candidato da tenere proposto secondo criteri dichiarati (percorso più stabile, nome più informativo, data più antica, presenza di un giudizio già assegnato), sempre modificabile dall'utente.
- **FR-050** L'app individua i **gruppi di quasi-duplicati** combinando similarità visiva e vicinanza temporale di scatto, con soglia regolabile e riorganizzazione visiva immediata dei gruppi al variare della soglia.
- **FR-051** Nessun duplicato, esatto o approssimato, viene eliminato senza conferma esplicita dell'utente; l'eliminazione passa dal Cestino di macOS.

### Area 11 - Selezione assistita (capacità c)

- **FR-052** Data una selezione di immagini, l'utente può chiedere all'app di proporre le **N migliori da tenere** (N predefinito 3, regolabile almeno tra 1 e 10).
- **FR-053** L'analisi procede nell'ordine di priorità stabilito: (1) raggruppamento per similarità visiva e temporale, (2) valutazione del soggetto — volti rilevati, qualità del volto, occhi aperti o chiusi, (3) qualità tecnica misurabile — nitidezza valutata sul soggetto e non sull'intero fotogramma, mosso, esposizione e clipping, rumore stimato, (4) punteggio estetico come criterio di spareggio finale.
- **FR-054** Per **ogni** immagine valutata l'app mostra il punteggio scomposto nei criteri che lo compongono, in forma leggibile ("a fuoco: alto — 2 volti, occhi aperti — esposizione corretta"), e non un singolo numero opaco.
- **FR-055** L'app dichiara sempre **perché** un'immagine è stata proposta e perché un'altra è stata scartata, in termini di criteri, così che l'utente possa dissentire con cognizione.
- **FR-056** L'utente può modificare la proposta prima di agire (aggiungere o togliere immagini dai "da tenere"), e nessuna immagine viene eliminata o spostata senza una conferma esplicita.
- **FR-057** L'analisi è eseguita **solo su richiesta e solo su una selezione**: aprire una cartella non innesca in nessun caso il calcolo dei punteggi di qualità o del punteggio estetico.
- **FR-058** L'analisi è annullabile in qualunque momento, mostra un avanzamento leggibile, e i risultati parziali già calcolati restano validi e memorizzati.
- **FR-059** Tutta l'analisi avviene in locale: nessuna immagine, nessun dato derivato e nessun metadato lascia il dispositivo in nessuna circostanza.

### Area 12 - Editing di base

- **FR-060** L'utente può ruotare un'immagine di 90° in entrambi i versi e capovolgerla orizzontalmente e verticalmente, anche su selezioni multiple.
- **FR-061** L'utente può ritagliare un'immagine con proporzioni libere o predefinite (1:1, 4:3, 3:2, 16:9), con riquadro trascinabile e valori visibili.
- **FR-062** Al salvataggio l'utente sceglie esplicitamente tra sovrascrivere l'originale e creare una copia; l'opzione predefinita è la copia. Creando una copia, il giudizio dell'immagine di partenza è replicato sulla copia insieme al suo sidecar.
- **FR-063** Il salvataggio preserva i metadati EXIF/IPTC dell'immagine di partenza, aggiornando i soli campi resi incoerenti dalla trasformazione (dimensioni, orientamento).

### Area 13 - Operazioni su file e reversibilità

- **FR-064** L'utente può spostare, copiare e rinominare singole immagini e selezioni verso una cartella di destinazione scelta, con gestione esplicita delle collisioni.
- **FR-065** L'eliminazione avviene **sempre** tramite il Cestino di macOS e mai con una cancellazione diretta.
- **FR-066** L'app espone una cronologia delle operazioni massive eseguite, con la possibilità di annullare un lotto specifico e non solo l'ultimo.
- **FR-067** Ogni operazione su file riporta un esito esplicito: quanti file elaborati, quanti saltati, quanti in errore e per quale motivo. Un errore su un singolo file non interrompe il lotto né lo lascia in stato indeterminato.
- **FR-068** L'utente può rivelare qualsiasi immagine nel Finder e aprirla con un'altra applicazione, senza perdere lo stato dell'app.

### Area 14 - Indice locale, identità e prestazioni

- **FR-069** L'app mantiene un indice locale di metadati, hash, dati di similarità e copia dei giudizi, e non ricalcola ciò che è già valido.
- **FR-070** L'indice distingue **identità** e **validità** come informazioni separate: l'identità dell'immagine (riferimento del filesystem, con il contenuto come riserva) determina a chi appartengono i giudizi; la validità (dimensione e data di modifica) determina cosa va ricalcolato. La scadenza della validità invalida i dati derivati e **non tocca mai i giudizi**.
- **FR-071** L'indice è integralmente ricostruibile: l'utente può svuotarlo dalle impostazioni senza perdere nessuna immagine e senza rendere l'app inutilizzabile. Prima dell'operazione l'app dichiara esattamente cosa verrà perso e cosa verrà recuperato dai sidecar alla successiva apertura delle cartelle.
- **FR-072** Alla riapertura di una cartella già indicizzata, la griglia è popolata dalla cache senza ricalcoli, e le modifiche avvenute nel frattempo sono riconciliate in sottofondo senza bloccare l'interazione.

### Area 15 - Permessi e primo avvio

- **FR-073** L'app non richiede l'Accesso completo al disco per funzionare, e non ne fa un prerequisito di primo avvio: l'utente apre una cartella e lavora.
- **FR-074** Ogni richiesta di accesso al filesystem avviene **dopo il gesto che la motiva** — l'apertura o il trascinamento di una cartella — e mai su una schermata preliminare; la motivazione mostrata nel dialogo di sistema spiega in una frase perché l'app ha bisogno di quell'accesso.
- **FR-075** Se l'accesso viene negato, l'app mostra uno stato che spiega cosa manca e come concederlo, con una via diretta al pannello di sistema corrispondente, e resta pienamente utilizzabile sulle cartelle già accessibili.
- **FR-076** L'app offre, come opzione e non come obbligo, la concessione dell'Accesso completo al disco per chi lavora su percorsi insoliti e vuole evitare ulteriori dialoghi, spiegando cosa cambia in concreto.

### Area 16 - Accessibilità

- **FR-077** Ogni funzione dell'MVP è raggiungibile da tastiera; nessuna azione richiede esclusivamente il mouse o il trackpad.
- **FR-078** Le immagini in griglia, i controlli e i campi del pannello metadati espongono etichette leggibili da VoiceOver; il valore dei metadati e il giudizio assegnato sono annunciabili senza aprire finestre aggiuntive.
- **FR-079** L'app rispetta le preferenze di sistema *Riduci movimento* e *Aumenta contrasto*, e supporta la dimensione del testo di sistema nei pannelli senza troncamenti.

---

## Non-Functional Requirements

<!-- archetipo:prd section=non_functional_requirements required=true -->

### Prestazioni e reattività

Sono i requisiti che governano il rischio primario del prodotto e vanno trattati come vincoli, non come obiettivi:

- **NFR-P1** Alla prima apertura di una cartella con 3.000 immagini, la prima schermata di anteprime è visibile entro **1 secondo**; la griglia è navigabile mentre il resto continua a caricarsi in sottofondo.
- **NFR-P2** Alla riapertura di una cartella già indicizzata la griglia è popolata **immediatamente** dalla cache, senza alcun ricalcolo; l'eventuale riconciliazione delle modifiche avvenute nel frattempo avviene in sottofondo e non ritarda la prima schermata.
- **NFR-P3** Lo spostamento della selezione con le frecce risponde entro **100 ms** anche mentre sono in corso lavori in sottofondo; l'interfaccia non si blocca mai, in nessuna operazione.
- **NFR-P4** Il pannello metadati si aggiorna entro **150 ms** dal cambio di selezione.
- **NFR-P5** Nessuna scansione bloccante all'apertura di una cartella: enumerazione, metadati, hash e analisi visiva sono lavori annullabili a priorità inferiore all'interazione.
- **NFR-P6** Il lavoro in sottofondo relativo a celle uscite dallo schermo è annullato immediatamente; la coda non cresce indefinitamente con lo scorrimento.
- **NFR-P7** L'occupazione di memoria resta stabile su cartelle da 10.000 immagini: le anteprime sono liberate al di fuori della finestra di visualizzazione.
- **NFR-P8** Il rilevamento dei duplicati esatti su 10.000 file non legge integralmente i file che possono essere esclusi negli stadi precedenti.
- **NFR-P9 Tetto di memoria dichiarato e verificato.** Esiste un limite superiore dichiarato all'occupazione di picco su una cartella da 50.000 immagini con scorrimento continuo, e una sessione di lunga durata non mostra crescita monotona dell'occupazione. Entrambe le soglie sono verificate da un test automatico eseguito in integrazione continua, che fallisce la build quando vengono superate. Nessun arresto per esaurimento di memoria è accettabile, tantomeno silenzioso.
- **NFR-P10 Il parallelismo è derivato dalla memoria, non dai core.** Lo scheduler ammette lavoro fino a un budget di memoria dichiarato, stimando il costo di ogni elemento dalle sue dimensioni in pixel; riduce il budget quando il sistema segnala pressione di memoria; e non decodifica mai un'immagine a piena risoluzione quando ne basta una ridimensionata.
- **NFR-P11 Quiete a riposo.** Con una cartella aperta e ferma, l'uso di CPU dell'app è indistinguibile da zero. Una raffica di modifiche al filesystem produce **al massimo una riconciliazione per finestra di quiete**, indipendentemente dal numero di eventi ricevuti, ed è verificata da un test con raffica sintetica.

### Affidabilità e integrità dei dati

- **NFR-A1** Nessuna operazione distruttiva senza conferma esplicita; nessuna eliminazione fuori dal Cestino di macOS.
- **NFR-A2** Ogni operazione massiva è preceduta da un'anteprima completa dell'effetto e registrata in un journal persistente che ne consente l'annullamento dopo il riavvio; il journal include i file collegati mossi insieme alle immagini.
- **NFR-A3** L'interruzione dell'app durante un lotto non lascia il filesystem in stato incoerente: il journal permette di riconoscere e riportare esattamente lo stato raggiunto.
- **NFR-A4** L'app non modifica mai un file che l'utente non ha esplicitamente incluso in un'operazione. In particolare, registrare un giudizio non comporta **in nessun caso** la riscrittura del file immagine.
- **NFR-A5** Un file corrotto o illeggibile non compromette il caricamento della cartella né di alcuna operazione sugli altri file. Lo stesso vale per un sidecar malformato o scritto da uno strumento sconosciuto: viene segnalato e ignorato, mai riscritto alla cieca.
- **NFR-A6** La scrittura di un sidecar è atomica: passa da un file temporaneo sullo stesso volume e da una rinomina atomica, così che un arresto anomalo non possa mai produrre un sidecar parziale né lasciare l'immagine senza il suo giudizio precedente.
- **NFR-A7** Nessuna perdita silenziosa di un giudizio: se la scrittura di un sidecar fallisce, il giudizio resta nell'indice, l'utente ne è informato e l'operazione è riprovabile.
- **NFR-A8** La correttezza della vista non dipende dalla completezza delle notifiche del filesystem: in ogni condizione, compresa la perdita di eventi dichiarata dal sistema, una riconciliazione riporta il catalogo in accordo con il disco.

### Sicurezza

- **NFR-S1 Nessuna rete a tempo di esecuzione.** L'app non invia immagini, metadati, dati derivati né telemetria a nessun servizio remoto, in nessuna circostanza. L'unica connessione ammessa è l'eventuale download iniziale del modello estetico, se si scegliesse di non includerlo nel bundle: sarebbe esplicita, verso un'origine dichiarata, verificata per integrità e completamente rinunciabile.
- **NFR-S2 Nessun account, nessuna credenziale, nessun dato personale raccolto.** Non esiste autenticazione perché non esiste nulla da autenticare.
- **NFR-S3 Distribuzione firmata.** Binario firmato con hardened runtime e notarizzato da Apple; nessuna disattivazione di Gatekeeper richiesta all'utente.
- **NFR-S4 Permesso minimo necessario.** L'app opera senza sandbox ma **non richiede l'Accesso completo al disco**: si affida al consenso contestuale che il sistema chiede per le categorie protette e all'accesso concesso dall'utente aprendo o trascinando una cartella. Il permesso più ampio è un'opzione, mai un prerequisito.
- **NFR-S5 Punto unico di scrittura.** Tutte le scritture, gli spostamenti e le eliminazioni passano da un unico livello di accesso al filesystem, che è il solo punto in cui il codice può modificare qualcosa, è coperto da test dedicati, ed è il punto d'innesto della futura sandbox.
- **NFR-S6 Dati sensibili nei metadati.** Le coordinate GPS sono trattate come informazione sensibile: mostrate su richiesta, mai incluse in nomi di file generati automaticamente, mai copiate in un sidecar, e rimovibili in esportazione (fase di crescita).
- **NFR-S7 Superficie delle dipendenze ridotta al minimo.** L'unica dipendenza esterna a tempo di esecuzione è GRDB.swift; tutto il resto è framework di sistema, e il formato dei sidecar è XML gestito senza librerie di terze parti. Ogni nuova dipendenza richiede una decisione architetturale registrata.
- **NFR-S8 Provenienza del modello.** Il modello estetico open source è versionato, la sua licenza è verificata come compatibile con la distribuzione, e la sua origine e conversione sono documentate nel repository.

### Integrazioni

Tutte le integrazioni sono con il sistema operativo o con formati standard aperti; non esiste alcuna integrazione con servizi di terze parti.

- **NFR-I1 QuickLook Thumbnailing** — generazione delle anteprime per tutti i formati supportati dal sistema, con riuso della cache di sistema.
- **NFR-I2 ImageIO** — lettura di metadati EXIF/IPTC/GPS/TIFF, decodifica sempre ridimensionata, scrittura in fase di salvataggio con preservazione dei metadati.
- **NFR-I3 Vision** — feature print dell'immagine per la similarità visiva, rilevamento volti, qualità di cattura del volto, landmark oculari.
- **NFR-I4 Core ML** — esecuzione locale del modello estetico open source, su richiesta e su insiemi già ridotti.
- **NFR-I5 Core Image e Metal** — trasformazioni geometriche, istogrammi, misure di nitidezza, con accelerazione GPU.
- **NFR-I6 File System Events** — rilevamento delle modifiche alla cartella aperta, con eventi a granularità di file, identificatore dell'ultimo evento persistito per riprendere dopo la chiusura dell'app, e gestione esplicita della segnalazione di eventi persi dal sistema.
- **NFR-I7 Cestino di macOS** — unica via di eliminazione, con ripristino garantito dal sistema.
- **NFR-I8 XMP (schema Basic)** — formato standard aperto per rating ed etichette nei sidecar, con l'obiettivo dichiarato di interoperare con i principali strumenti fotografici che lo leggono e lo scrivono.
- **NFR-I9 Servizi Finder** — rivela nel Finder, apri con, foglio di condivisione di sistema.
- **NFR-I10 Accessibilità di sistema** — VoiceOver, *Riduci movimento*, *Aumenta contrasto*, dimensione del testo.
- **NFR-I11 Nessuna integrazione con la libreria Foto di macOS** nell'MVP: scelta esplicita coerente con "la cartella è la fonte di verità".

---

## Next Steps

<!-- archetipo:prd section=next_steps required=true -->

1. **Backlog** - Esegui `/archetipo-spec` per trasformare questo PRD in un backlog
2. **Design** - Esegui `/archetipo-design` per i mockup dell'interfaccia (quando applicabile)
3. **Validazione** - Rivedi con gli stakeholder e metti alla prova gli assunti più rischiosi

---

_PRD generato tramite ARchetipo Product Inception - 2026-08-24_
_Revisione architetturale 1.1 - 2026-08-25_
_Sessione condotta da: alessandro.giardina@intre.it con il team ARchetipo_
