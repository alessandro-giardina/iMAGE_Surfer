---
type: reference
title: PRD di iMAGE Surfer
description: Documento di requisiti di prodotto di iMAGE Surfer, prodotto dalla sessione di inception del 2026-08-24; unica fonte dell'intento in assenza di codice
status: generated
sources:
  - path: docs/PRD.md
    role: original
---
# PRD di iMAGE Surfer

Concetto di riferimento che conserva il contenuto del documento di prodotto originale, `docs/PRD.md`.

**Come leggerlo.** Tutto ciò che segue è **intento di prodotto**, non comportamento osservato: al momento in cui questa pagina è stata creata il repository non conteneva codice applicativo, quindi nessuna affermazione qui sotto è verificata contro un'implementazione. Ogni riuso di questo contenuto altrove nella Wiki deve restare attribuito a questo documento fino a quando esiste codice che lo dimostri. Vedi [Panoramica](/overview.md) e [Mappa del codice](/engineering/code-map.md).

I marcatori strutturali `archetipo:prd` del documento originale, che appartengono al contratto di validazione del PRD e non al suo contenuto, sono stati omessi; il resto del testo è conservato integralmente.

---

# iMAGE Surfer - Product Requirements Document

**Autore:** ARchetipo
**Data:** 2026-08-24
**Versione:** 1.0

---

## Elevator Pitch

> Il Finder di macOS è un gestore di file che tollera le immagini. iMAGE Surfer è l'opposto: tratta una cartella come un rullino da lavorare, non come un elenco di file. Apri qualsiasi cartella, vedi solo le immagini, le giudichi grandi sullo schermo muovendoti con le sole frecce, leggi i metadati senza aprire nulla, e quando ti trovi davanti a otto scatti quasi identici l'app ti dice quali tenere e perché. Nessuna importazione, nessun catalogo, nessun lock-in: le tue foto restano dove sono.
>
> Per **chi accumula migliaia di immagini in cartelle su macOS e le deve selezionare, rinominare e riorganizzare a mano**, che ha il problema di **usare un file manager generalista per un lavoro squisitamente visivo — anteprime minuscole, metadati sepolti in Get Info, navigazione che richiede il mouse e zero aiuto nella scelta tra scatti simili**, **iMAGE Surfer** è un **browser e banco di triage per immagini, nativo macOS** che **permette di vedere, giudicare e riorganizzare migliaia di foto senza mai lasciare la tastiera, con selezione assistita da AI che gira interamente in locale**. A differenza del **Finder (e dei cataloghi tipo Lightroom o Foto di macOS)**, il nostro prodotto **unisce la velocità di uno strumento professionale di triage all'assenza totale di importazione: la cartella sul disco resta l'unica fonte di verità, e ogni operazione massiva è mostrata in anteprima e annullabile**.

---

## Vision

Rendere il lavoro su un insieme di immagini — guardarle, sceglierle, scartarle, rinominarle, ordinarle — un'attività fluida, veloce e a tastiera, sfruttando fino in fondo ciò che macOS già offre: decodifica accelerata di ogni formato fotografico, visione artificiale sul Neural Engine, Cestino reversibile, notifiche del filesystem. Tutto in locale, senza cloud, senza account, senza spedire una sola immagine fuori dal Mac.

L'obiettivo di lungo periodo non è diventare un editor fotografico né un catalogo: è diventare **il livello di curation che manca tra il filesystem e gli strumenti di editing**. Il posto dove decidi *cosa merita di esistere* e *dove deve stare*, prima di aprire qualunque altra cosa.

### Differenziatore di Prodotto

Tre scelte, tenute insieme, che nessuna alternativa attuale combina:

1. **La cartella è la fonte di verità.** L'app non importa, non sposta a tua insaputa, non crea una libreria proprietaria. L'indice locale è una cache buttabile e ricostruibile: se cancelli il database, non perdi nulla. Questo è l'opposto esatto del modello Lightroom/Foto.
2. **Il triage a tastiera come interazione primaria, non come scorciatoia.** Frecce per muoversi, spazio per l'anteprima grande, un tasto per il rating, un tasto per marcare da scartare. Il mouse è opzionale, non necessario.
3. **L'AI argomenta, non decreta.** Il sistema non dice "questa è la più bella": raggruppa gli scatti quasi identici, li mette a confronto e mostra le ragioni misurabili di una proposta (nitidezza, volti rilevati, occhi aperti, esposizione, punteggio estetico). La decisione finale, e l'unico dito sul grilletto, restano dell'utente.

---

## User Personas

### Persona 1: Marco - il curatore di cartelle

**Ruolo:** Professionista tecnico (sviluppo/consulenza), fotografo per passione, unico proprietario e amministratore del proprio Mac
**Età:** 35-50 | **Background:** Utente macOS avanzato da anni. Scatta con smartphone e con una mirrorless, scarica le schede a mano in cartelle organizzate per anno/evento. Ha volutamente rifiutato Lightroom e la libreria di Foto: non vuole che un software si metta in mezzo tra lui e i suoi file.

**Obiettivi:**
- Passare da 300 scatti scaricati a 40 scatti tenuti in pochi minuti, non in una serata.
- Dare ai file nomi che avranno ancora senso tra dieci anni, senza rinominare a mano.
- Sapere che una cartella "fatta" è davvero pulita: nessun duplicato, nessuno scarto rimasto dentro.
- Non dipendere da nessun servizio cloud e da nessun formato proprietario.

**Punti di dolore:**
- In una cartella vede `.DS_Store`, PDF, ZIP e sidecar mescolati alle foto: deve filtrare a occhio ogni volta.
- Le anteprime del Finder sono troppo piccole per capire se uno scatto è a fuoco: deve aprire l'immagine in un'altra app, guardarla, chiuderla, e ripetere. Decine di volte.
- Non può scorrere le anteprime con le frecce: ogni passaggio richiede mouse o trackpad.
- Per leggere ISO, obiettivo o ora di scatto serve tasto destro → Get Info, una finestra per immagine.
- Davanti a otto scatti dello stesso momento nessuno strumento lo aiuta: sceglie a intuito, oppure — più spesso — non sceglie e tiene tutto.

**Comportamenti e strumenti:**
Finder, Anteprima, QuickLook, occasionalmente un editor per un ritaglio. Lavora a tastiera dove può. Diffida delle scelte automatiche irreversibili, ma si fida di uno strumento che gli mostra prima cosa farà.

**Motivazioni:** Recuperare tempo su un lavoro ripetitivo che oggi lo frustra; avere un archivio di cui va fiero e di cui è padrone.
**Competenza tecnica:** Alta. Sa cosa sono EXIF, hash, spazio colore. Non ha bisogno che gli si semplifichi la realtà, ha bisogno che gli si risparmino i clic.

#### Percorso Cliente - Marco

| Fase | Azione | Pensiero | Emozione | Opportunità |
|---|---|---|---|---|
| Consapevolezza | Dopo l'ennesima serata a scremare una cartella nel Finder, cerca "image browser macOS keyboard" | "Non può essere che nel 2026 io stia ancora aprendo e chiudendo file uno per uno" | Frustrazione, stanchezza | Comunicare il prodotto sulla frustrazione esatta, non su una lista di funzioni |
| Considerazione | Valuta Lightroom, Photo Mechanic, Foto di macOS | "Tutti vogliono importare le mie foto in una loro libreria. Io voglio solo *guardare* la mia cartella" | Diffidenza | Dichiarare in prima riga: nessuna importazione, la cartella resta la fonte di verità |
| Primo utilizzo | Trascina una cartella con 800 foto sull'app | "Vediamo quanto ci mette prima di mostrarmi qualcosa" | Curiosità mista a scetticismo | Prima anteprima visibile in meno di un secondo; nessun dialogo di setup, nessun account |
| Uso regolare | Ogni scarico di schede finisce nell'app: triage a frecce, rating, gruppi di simili, rinomina massiva, smistamento in sottocartelle | "Quaranta minuti di lavoro diventati cinque" | Fiducia, controllo | Ricordare le cartelle recenti e i pattern di rinomina usati; rendere ogni operazione massiva annullabile |
| Advocacy | Lo mostra a un amico fotografo e gli manda il `.dmg` | "Questo risolve un problema che abbiamo tutti e nessuno risolve" | Soddisfazione | Prevedere un percorso di distribuzione a terzi (sandbox e firma) come evoluzione |

---

### Persona 2: Sara - la selezionatrice sotto scadenza

**Ruolo:** Content/social manager in una PMI; riceve materiale fotografico da fotografi esterni e colleghi
**Età:** 25-40 | **Background:** Ogni settimana le arriva una cartella condivisa con 200-500 immagini di un evento o di un prodotto. Deve consegnare pochi scatti selezionati, nominati secondo la convenzione aziendale e ordinati in sottocartelle per canale.

**Obiettivi:**
- Ridurre 400 immagini a 12 buone, oggi, non domani.
- Rispettare la convenzione di naming aziendale senza rinominare un file per volta.
- Non consegnare mai due volte la stessa foto con nomi diversi.

**Punti di dolore:**
- Riceve raffiche: dieci scatti dello stesso sorriso, e deve capire in quale gli occhi sono aperti guardando anteprime di 128 pixel.
- Rinomina a mano, sbaglia, e il conteggio progressivo salta.
- Trova quasi-duplicati e duplicati esatti mescolati e non ha modo di distinguerli.
- Non è a suo agio con strumenti da fotografo: se deve imparare un catalogo, torna al Finder.

**Comportamenti e strumenti:**
Finder, Anteprima, Canva, cartelle condivise. Usa il mouse più della tastiera, ma impara volentieri due o tre scorciatoie se le vede ripagate subito.

**Motivazioni:** Consegnare in tempo, senza errori evidenti, senza diventare un'esperta di software fotografico.
**Competenza tecnica:** Media. Sa cos'è un JPEG e cosa non è; di EXIF conosce la data e poco altro.

#### Percorso Cliente - Sara

| Fase | Azione | Pensiero | Emozione | Opportunità |
|---|---|---|---|---|
| Consapevolezza | Un collega le mostra l'app durante una consegna in ritardo | "Se mi dice davvero quale foto ha gli occhi aperti, mi cambia la giornata" | Speranza | Dimostrare il valore su un gruppo di raffica, che è il caso in cui il dolore è massimo |
| Considerazione | Teme che sia "uno strumento da fotografi" | "Non ho tempo di imparare Lightroom" | Timore di complessità | Nessuna importazione, nessuna configurazione: apri la cartella e sei operativa |
| Primo utilizzo | Seleziona 10 scatti simili e chiede "tieni le 3 migliori" | "Perché proprio queste tre?" | Sospetto | Mostrare sempre le motivazioni misurabili accanto alla proposta; nessuna cancellazione automatica |
| Uso regolare | Triage con rating, gruppi di simili, rinomina massiva su pattern aziendale, smistamento in sottocartelle per canale | "Ho un flusso, e lo ripeto identico ogni settimana" | Sollievo, competenza | Salvare i pattern e le regole ricorrenti come preset riutilizzabili (crescita) |
| Advocacy | Diventa la convenzione del team | "Le consegne le facciamo così" | Orgoglio professionale | Esportare/condividere i preset di naming e le regole di smistamento (crescita) |

---

## Brainstorming Insights

> Scoperte chiave e direzioni alternative esplorate durante la sessione di inception.

### Assunti Messi in Discussione

- **"Le cinque frustrazioni sono cinque funzioni da aggiungere."** Falso: sono un unico problema. Il Finder è un file manager che tollera le immagini. La conseguenza progettuale è che il cuore dell'app non è la griglia di anteprime, ma il **ciclo di triage** guarda → giudica → agisci → prossima, interamente a tastiera. Ogni funzione va valutata su quanto accorcia quel ciclo.
- **"Esiste un 'migliore' oggettivo che un modello può calcolare."** In gran parte falso, e il prodotto ne dipende. Su una raffica di scatti quasi identici "migliore" significa quasi sempre grandezze misurabili (a fuoco, non mosso, occhi aperti, esposizione sana) e solo di rado "più bello". Da qui la regola non negoziabile: **l'AI argomenta, non decreta**, e non cancella mai nulla da sola. Il punteggio estetico è ammesso come criterio, ma resta l'ultimo e il più debole, mostrato accanto agli altri e non al loro posto.
- **"L'AI è la funzione che vende, quindi va messa al centro."** Vera solo a metà. Il differenziatore commerciale è l'AI; il differenziatore d'uso quotidiano è la **latenza**. Un'app che scandisce 4.000 file calcolando embedding prima di mostrare la prima anteprima viene abbandonata al terzo utilizzo, quale che sia la qualità del modello. Conseguenza architetturale: analisi AI **solo su richiesta, solo su una selezione**, mai in scansione di cartella.
- **"Le frecce sono un dettaglio di comodità."** Falso: sono l'intero contratto di interazione. Se le frecce spostano la selezione, allora *tutto* il resto deve essere raggiungibile senza lasciare la tastiera, altrimenti la mano torna al mouse e il vantaggio svanisce. Questo vincola la mappa dei tasti a essere completa dal primo giorno, non arricchita in seguito.
- **"Bisogna scegliere un solo criterio di selezione."** Superato dal confronto: i criteri sono tre e sono **in cascata ordinata** — prima si raggruppano gli scatti quasi identici, poi dentro il gruppo si valuta il soggetto (volti, occhi aperti), infine la qualità tecnica fa da spareggio. Senza il primo passo, "le tre migliori di 40 foto" non è una domanda ben posta.

### Nuove Direzioni Scoperte

- **Anti-problem ("come rendiamo questa app inutilizzabile?").** Le risposte hanno prodotto i vincoli non funzionali più utili del documento: scansione bloccante all'apertura, coda di decodifica senza cancellazione allo scroll, cancellazioni irreversibili, ricalcolo dell'indice a ogni avvio. Ognuno di questi anti-pattern è diventato un requisito rovesciato.
- **"E se togliessimo l'AI?" (what if).** L'app resterebbe utile: filtro dei soli file immagine, anteprime grandi, navigazione a frecce e pannello metadati risolvono già quattro frustrazioni su cinque. Questo dà un ordine di implementazione robusto: **il triage a tastiera deve stare in piedi da solo**, e la parte AI si innesta sopra un'app già funzionante. Riduce drasticamente il rischio d'esecuzione.
- **Audience flip (dal proprietario del Mac al team).** Immaginando l'app in mano a un reparto marketing sono emerse due esigenze assenti nel brief originale ma naturali: **preset condivisibili** di rinomina e smistamento, e la distribuzione a terzi (che implica sandbox). Entrambe rinviate consapevolmente alla fase di crescita, ma l'architettura non deve precluderle: le regole vanno modellate come dati serializzabili, non come codice.
- **Il journal delle operazioni come funzione, non come dettaglio tecnico.** Registrare ogni rinomina/spostamento massivo rende possibile un "annulla" che sopravvive alla chiusura dell'app. È ciò che trasforma un'operazione su 800 file da atto di fede in operazione normale — ed è quindi un elemento di fiducia, non solo di robustezza.
- **Il pannello metadati come acceleratore di selezione.** Nato per risolvere la frustrazione 4, si è rivelato utile anche altrove: ISO alto e tempo di scatto lungo *predicono* rumore e mosso. Gli stessi metadati che l'utente legge alimentano l'ordinamento dei candidati.

### Assunti da Validare

- **Soglia di similarità.** Il valore iniziale della distanza tra feature print per considerare due immagini "quasi duplicate" è una stima da calibrare su materiale reale. Il PRD fissa un default e impone che la soglia sia regolabile con feedback visivo immediato. *Domanda aperta: quale valore funziona su raffiche di smartphone rispetto a scatti di mirrorless?*
- **Utilità reale del punteggio estetico.** È stato incluso nell'MVP su scelta esplicita dell'utente. Resta da verificare che aggiunga informazione oltre ai criteri misurabili e che non venga percepito come arbitrario. *Se dopo l'uso reale non sposta le decisioni, va declassato a criterio opzionale disattivabile.*
- **Peso e provenienza del modello estetico.** Un modello open source di image-quality assessment convertito in Core ML incide sulle dimensioni del bundle. *Domanda aperta: bundle unico più grande, oppure download al primo utilizzo? La seconda strada introduce l'unica connessione di rete dell'app.*
- **RAW rinviato alla crescita.** Assunto: il flusso di lavoro attuale è basato su JPEG/HEIC. *Se in pratica gli scatti importanti sono RAW, la priorità va rivista subito: il modello dei dati (coppia RAW+JPEG affiancata, anteprima incorporata) non è un dettaglio da aggiungere dopo senza costi.*
- **Ricorsività delle operazioni massive.** Assunto per l'MVP: le operazioni agiscono sulla cartella corrente, non sull'albero sottostante. *Da confermare: la ricorsione moltiplica i modi in cui un'operazione massiva può fare danni.*
- **Nessuna integrazione con la libreria Foto di macOS.** Assunto: le immagini di interesse vivono in cartelle del filesystem. *Da confermare.*
- **Numero di "migliori" da tenere.** Il brief dice "2 o 3": modellato come parametro (default 3) e non come costante.

### Rischi Principali

- **Rischio di esecuzione — latenza percepita.** È il rischio primario. Se aprire una cartella da 3.000 immagini non è immediato, l'app perde contro il Finder a prescindere da tutto il resto. Mitigazione: anteprime dal servizio di sistema con cache su disco, decodifica solo di ciò che è visibile, cancellazione aggressiva della coda allo scroll, indice persistente per non ricalcolare mai due volte.
- **Rischio di adozione — sfiducia nell'AI.** Una proposta di selezione non spiegata viene disattivata dopo pochi utilizzi. Mitigazione: motivazioni sempre visibili, soglie regolabili, nessuna azione distruttiva automatica, l'utente conferma sempre.
- **Rischio di perdita dati sulle operazioni massive.** Rinominare o spostare centinaia di file è la funzione più utile e la più pericolosa. Mitigazione a tre livelli: anteprima obbligatoria prima dell'esecuzione, journal persistente con annullamento, eliminazioni sempre nel Cestino di macOS e mai `unlink`.
- **Rischio tecnico — coerenza della cache.** Un indice che si disallinea dal filesystem produce anteprime sbagliate o file fantasma, il difetto che più rapidamente distrugge la fiducia. Mitigazione: chiave di validità basata su identità e mtime del file, monitoraggio degli eventi del filesystem, indice sempre ricostruibile da zero.
- **Rischio di scope — l'editing.** "Editing di base" è un imbuto che può ingoiare l'MVP. Mitigazione: l'MVP contiene solo trasformazioni geometriche (rotazione, capovolgimento, ritaglio). Regolazioni tonali ed editing non distruttivo sono esplicitamente fuori.
- **Rischio operativo — assenza di sandbox.** La scelta di un'app personale non in sandbox richiede all'utente di concedere l'Accesso completo al disco e limita la distribuzione a terzi. Accettato consapevolmente per l'MVP; la sandbox è una funzione di crescita e l'architettura non deve dare per scontato l'accesso illimitato al filesystem.

---

## Product Scope

### MVP - Minimum Viable Product

Il criterio di taglio dell'MVP: **risolvere tutte e cinque le frustrazioni dichiarate, più le tre capacità richieste (a, b, c), sulla scala reale di 10.000-50.000 immagini**. Tutto ciò che non serve a questo è fuori.

**1. Apertura e navigazione delle cartelle**
- Apertura di una cartella qualsiasi tramite trascinamento, dialogo di sistema, cartelle recenti o preferiti nella barra laterale.
- **Solo le immagini sono visibili**: ogni altro tipo di file è escluso dalla vista (frustrazione 1). Contatore del contenuto non-immagine, senza mai mostrarlo mescolato.
- Ordinamento per nome, data di scatto, data di modifica, dimensione, rating.
- Aggiornamento automatico quando la cartella cambia sotto l'app.

**2. Visualizzazione a griglia e anteprima grande**
- Griglia di anteprime con dimensione della cella regolabile fino a molto grande (frustrazione 2), fluida su migliaia di elementi.
- Anteprima grande a pannello e a schermo intero, con zoom fino a 1:1 e panoramica.
- **Navigazione integralmente a frecce** in griglia e in anteprima grande, senza mai passare dal mouse (frustrazione 3); selezione multipla da tastiera.

**3. Metadati sempre a portata d'occhio**
- Pannello metadati permanente e commutabile con un tasto: dati file, dimensioni, EXIF (fotocamera, obiettivo, ISO, tempo, diaframma, focale, data/ora di scatto), IPTC, GPS, spazio colore (frustrazione 4).
- Il pannello segue la selezione senza latenza percepibile; per selezioni multiple mostra i valori comuni.

**4. Giudizio e marcatura**
- Rating 1-5 stelle e marcatura "da scartare" da tastiera, memorizzati nell'indice locale.
- Filtri per rating, per marcatura, per formato, per intervallo di date.

**5. Operazioni su file, singole e massive**
- Spostamento, copia, rinomina di singole immagini e di selezioni.
- Eliminazione **sempre nel Cestino di macOS**, con annullamento.
- **Rinomina massiva guidata da pattern** su regole e metadati (capacità a), con anteprima obbligatoria `da → a`, politica esplicita per collisioni e metadati mancanti, e annullamento persistente.
- **Creazione massiva di sottocartelle e smistamento per regole** (capacità b): per data di scatto, fotocamera, formato, rating, marcatura; anteprima e annullamento con lo stesso contratto della rinomina.

**6. Duplicati**
- Rilevamento dei **duplicati esatti** per contenuto (byte-identici anche con nome diverso) e pannello di risoluzione che propone quale copia tenere.
- Rilevamento dei **gruppi di quasi-duplicati** (raffiche, scatti dello stesso momento) con soglia regolabile.

**7. Selezione assistita — "tieni le migliori N"** (capacità c, frustrazione 5)
Pipeline in cascata sull'ordine di priorità stabilito:
1. raggruppamento per similarità visiva e vicinanza temporale;
2. analisi del soggetto: volti rilevati, qualità del volto, occhi aperti/chiusi;
3. qualità tecnica misurabile: nitidezza sul soggetto, mosso, esposizione e clipping, rumore stimato;
4. punteggio estetico da modello open source locale, come criterio di spareggio finale.
- Proposta di N immagini da tenere (default 3, regolabile) **con le motivazioni sempre visibili** per ciascun candidato.
- Nessuna azione distruttiva automatica: l'utente conferma, e l'esito è comunque reversibile.
- Esecuzione **solo su richiesta e solo su una selezione**, mai come scansione di cartella.

**8. Editing di base**
- Rotazione di 90°, capovolgimento orizzontale e verticale, ritaglio con proporzioni libere e predefinite.
- Salvataggio come copia oppure sovrascrittura, con scelta esplicita e conservazione dei metadati.

**9. Fondamenta trasversali**
- Indice locale persistente come cache buttabile: la cartella resta la fonte di verità.
- Mappa dei tasti completa e visibile in un pannello di aiuto.
- Accessibilità: etichette VoiceOver sui metadati e sui controlli, rispetto di *Riduci movimento* e *Aumenta contrasto*, area dei bersagli di clic dimensionata per l'uso reale, operabilità totale da tastiera.

### Growth Features (Post-MVP)

- **Supporto RAW** (CR2/CR3, NEF, ARW, DNG, ORF) con gestione delle coppie RAW+JPEG affiancate.
- **Editing non distruttivo**: regolazioni tonali (esposizione, contrasto, saturazione, bilanciamento) con file affiancato e storico reversibile; l'originale non viene mai toccato.
- **Preset riutilizzabili e condivisibili** per pattern di rinomina e regole di smistamento.
- **Confronto affiancato** di 2-4 immagini con zoom sincronizzato — il modo naturale di risolvere un gruppo di quasi-duplicati.
- **Ricerca e filtri cross-cartella** sull'indice locale (per fotocamera, data, rating, formato).
- **Scrittura di parole chiave e tag IPTC** direttamente nei file.
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

> **Proposta da:** Leonardo (Architect)

### System Architecture

Applicazione **nativa macOS, monoprocesso, interamente locale**: nessun server, nessuna rete a tempo di esecuzione (unica eccezione possibile, il download iniziale del modello estetico se non incluso nel bundle), nessun account.

Il vincolo "solo macOS" è sfruttato deliberatamente: le tre capacità più costose del prodotto — decodifica veloce di ogni formato fotografico, embedding di similarità visiva, rilevamento e valutazione dei volti — sono **già presenti nel sistema operativo**, accelerate su GPU e Neural Engine. Non vengono reimplementate né importate come dipendenze.

Il flusso dei dati è una pipeline a stadi, con l'indice locale come memoria dei risultati già calcolati:

```text
Cartella su disco
   │  (enumerazione + filtro per tipo immagine, via UTType)
   ▼
Catalogo in memoria (identità file: volume + inode + mtime + size)
   │                                    │
   │ (su richiesta, per celle visibili) │ (letto/scritto)
   ▼                                    ▼
Servizio anteprime  ◀──────────  Indice SQLite (cache buttabile)
   │  QuickLook + cache su disco        ▲
   ▼                                    │
Griglia / Anteprima grande              │
   │                                    │
   │ (su richiesta, su una selezione)   │
   ▼                                    │
Pipeline di analisi ────────────────────┘
   raggruppamento → soggetto → qualità tecnica → estetica
   │
   ▼
Proposta con motivazioni  →  conferma utente  →  Operazioni su file
                                                  │ (journal + Cestino)
                                                  ▼
                                            Annullamento persistente
```

**Pattern Architetturale:** MVVM su SwiftUI con nucleo di dominio in pacchetti SPM indipendenti dalla UI; concorrenza strutturata con attori; pipeline a stadi con code delimitate e cancellazione; indice locale in sola cache (la fonte di verità è il filesystem).

**Componenti Principali:**

- **`Catalog`** — enumerazione della cartella, filtro per tipo immagine tramite `UTType`, identità e validità dei file, monitoraggio degli eventi del filesystem, ordinamenti e filtri. Non conosce la UI.
- **`Metadata`** — lettura di EXIF/IPTC/GPS/TIFF e proprietà immagine tramite ImageIO (`CGImageSource`); normalizzazione in un modello tipizzato e stabile, tollerante ai metadati assenti.
- **`Thumbnails`** — generazione anteprime tramite QuickLook Thumbnailing con cache su disco a due misure (griglia e anteprima grande); scheduler con priorità alle celle visibili e cancellazione immediata di quelle uscite dallo schermo; decodifica ridimensionata via ImageIO per lo zoom 1:1.
- **`Duplicates`** — duplicati esatti a tre stadi (dimensione → hash parziale di testa e coda → SHA-256 completo solo su collisione); quasi-duplicati per distanza tra feature print di Vision combinata alla vicinanza temporale EXIF, con clustering a soglia.
- **`Quality`** — analisi del soggetto (rilevamento volti, qualità di cattura del volto, landmark oculari per occhi aperti/chiusi) e della qualità tecnica (nitidezza per varianza del Laplaciano calcolata **sul soggetto ritagliato** e non sull'intero fotogramma, istogramma per esposizione e clipping, stima del rumore) su immagine ridimensionata; punteggio estetico da modello Core ML come ultimo criterio. Restituisce sempre un punteggio **scomposto e spiegabile**, mai un numero unico.
- **`FileOps`** — spostamento, copia, rinomina, eliminazione nel Cestino; motore di rinomina massiva basato su pattern; motore di smistamento in sottocartelle basato su regole; **anteprima obbligatoria (dry-run)** e **journal persistente delle operazioni** che rende annullabile un lotto anche dopo il riavvio dell'app.
- **`IndexStore`** — schema e accesso a SQLite: metadati, hash, feature print, rating e marcature, journal delle operazioni. Ricostruibile da zero per progetto.
- **`UI`** — SwiftUI per la struttura, la barra laterale, i pannelli e i dialoghi; ponte AppKit su `NSCollectionView` per la griglia, che su decine di migliaia di celle regge dove una griglia SwiftUI pura non arriva. Mappa dei tasti centralizzata in un unico punto, non sparsa nelle viste.

### Technology Stack

| Livello | Tecnologia | Versione | Motivazione |
|---|---|---|---|
| Linguaggio | Swift | 6.x (concorrenza stretta) | Unico linguaggio di prima classe per le API di sistema che costituiscono il valore dell'app; la concorrenza strutturata è esattamente il modello richiesto dalle pipeline con cancellazione |
| Piattaforma applicativa | AppKit + Swift Concurrency | macOS 15+ | Il target è una sola piattaforma; nessun livello di astrazione multipiattaforma da mantenere |
| Framework di interfaccia | SwiftUI, con ponte AppKit (`NSCollectionView`) per la griglia | macOS 15+ | SwiftUI per velocità di costruzione di pannelli e dialoghi; `NSCollectionView` dove serve riuso di celle e fluidità su decine di migliaia di elementi |
| Anteprime e decodifica | QuickLook Thumbnailing + ImageIO + Core Image | di sistema | Supporto nativo di HEIC, TIFF, WebP e (in prospettiva) RAW senza dipendenze; decodifica ridimensionata e trasformazioni accelerate |
| Visione artificiale | Vision (feature print immagine, rilevamento e qualità volti, landmark) | di sistema | Embedding di similarità e valutazione volti sul Neural Engine: ordini di grandezza più rapidi di qualunque equivalente importato |
| Modello estetico | Modello open source di image-quality assessment convertito in Core ML | Core ML di sistema | Aggiunge il criterio di gradimento richiesto; eseguito **solo su gruppi già formati e solo su richiesta**, quindi con costo invisibile nel flusso normale |
| Database | SQLite | 3 (di sistema) | Indice locale a file unico, senza processi da gestire; adeguato con margine a 10-50k immagini |
| Accesso ai dati | GRDB.swift | 7.x | Accesso SQLite tipizzato e testabile in Swift, con migrazioni versionate e osservazione delle modifiche |
| Autenticazione | Nessuna | — | App locale monoutente, senza account e senza servizi remoti |
| Test | Swift Testing (unità e integrazione) + XCUITest (percorsi critici a tastiera) | di sistema | I moduli SPM sono testabili senza avviare l'interfaccia; XCUITest copre la navigazione a tastiera, che è il contratto d'uso primario |

### Project Structure

**Pattern organizzativo:** target applicativo Xcode sottile sopra pacchetti SPM locali per dominio; ogni pacchetto testabile in isolamento senza avviare la UI.

```text
iMAGE-Surfer/
├── iMAGESurfer.xcodeproj
├── App/                          # target applicativo: ciclo di vita, finestre, comandi, cablaggio
│   ├── iMAGESurferApp.swift
│   ├── Commands/                 # menu e mappa dei tasti centralizzata
│   ├── Resources/                # icone, Assets, modello Core ML compilato
│   └── iMAGESurfer.entitlements
├── Packages/
│   ├── Catalog/                  # enumerazione, filtro tipi, identità file, eventi FS
│   ├── Metadata/                 # ImageIO -> modello metadati tipizzato
│   ├── Thumbnails/               # QuickLook + cache su disco + scheduler con cancellazione
│   ├── Duplicates/               # hash esatti + clustering quasi-duplicati
│   ├── Quality/                  # Vision, Core Image, Core ML: punteggi scomposti
│   ├── FileOps/                  # rinomina/smistamento massivi, dry-run, journal, Cestino
│   ├── IndexStore/               # schema SQLite, migrazioni, accesso (GRDB)
│   └── DesignSystem/             # componenti condivisi, tipografia, accessibilità
├── Tests/                        # test di integrazione trasversali + fixture immagini
│   └── Fixtures/                 # set minimo: raffiche, duplicati, EXIF mancanti, HEIC, orientamenti
├── Scripts/
│   ├── build-dmg.sh              # pacchettizzazione e notarizzazione
│   └── lint.sh
├── docs/                         # PRD, wiki, mockup
└── .github/workflows/ci.yml
```

### Development Environment

Ambiente completamente locale, senza servizi da avviare: si apre il progetto Xcode e si esegue. Nessun contenitore, nessun database esterno, nessuna variabile d'ambiente obbligatoria.

Prima esecuzione: concedere all'app l'**Accesso completo al disco** in Impostazioni di Sistema → Privacy e sicurezza, coerentemente con la scelta di un'app personale non in sandbox. Le fixture di test (raffiche reali, duplicati esatti, immagini senza EXIF, HEIC, orientamenti EXIF non standard) sono versionate nel repository: sono la difesa contro i casi limite che si scoprono altrimenti solo in uso.

**Strumenti richiesti:** macOS 15 o successivo su Apple Silicon; Xcode 16 o successivo (Swift 6); `swift-format` e SwiftLint per lo stile; `xcodebuild` per build e test da riga di comando; `notarytool` e `create-dmg` per la distribuzione; Python con `coremltools` **solo** in fase di conversione del modello estetico, mai a tempo di esecuzione.

### CI/CD & Deployment

**Strumento di build:** `xcodebuild` (SPM per la risoluzione delle dipendenze dei pacchetti locali e di GRDB).

**Pipeline:** GitHub Actions su runner macOS. Ad ogni push: `swift-format --lint` e SwiftLint → build dei pacchetti SPM → test unitari di tutti i pacchetti → build del target applicativo → test XCUITest sui percorsi critici a tastiera. Su tag di versione: build in configurazione Release con hardened runtime, firma, notarizzazione, creazione del `.dmg` e pubblicazione come artefatto della release.

**Deployment:** distribuzione **manuale come `.dmg` notarizzato**, non in sandbox, secondo la scelta "app personale". Nessun canale di aggiornamento automatico nell'MVP (rinviato alla crescita insieme alla distribuzione a terzi).

**Infrastruttura di destinazione:** il Mac dell'utente. Nessuna infrastruttura server, nessun servizio remoto, nessuna telemetria.

### Architecture Decision Records (ADR)

- **ADR-001 — App nativa Swift/SwiftUI, non Electron o multipiattaforma.** *Decisione:* nativa. *Motivo:* le tre capacità portanti (decodifica di ogni formato fotografico, embedding di similarità, valutazione volti) sono servizi di sistema accelerati su hardware; in un runtime web andrebbero reimportate come dipendenze pesanti e girerebbero drasticamente più lente, colpendo esattamente il rischio primario del prodotto. *Conseguenza:* il codice non è portabile fuori da macOS — accettato come vincolo dichiarato del prodotto, non come limite.
- **ADR-002 — Anteprime da QuickLook Thumbnailing, non decodifica propria.** *Decisione:* il servizio di sistema è la sorgente primaria delle anteprime, con ImageIO come riserva e per lo zoom 1:1. *Motivo:* copertura gratuita dei formati (HEIC, TIFF, WebP, e RAW quando arriverà) e riuso della cache di sistema. *Conseguenza:* si dipende da una qualità di anteprima non controllata nel dettaglio; accettabile per la griglia, non per lo zoom, dove si decodifica direttamente.
- **ADR-003 — L'indice SQLite è una cache buttabile; la cartella è la fonte di verità.** *Decisione:* nessuna importazione, nessuna libreria proprietaria; l'indice è ricostruibile integralmente e la sua cancellazione non perde immagini. *Motivo:* è il differenziatore centrale rispetto ai cataloghi. *Conseguenza:* rating e marcature vivono nell'indice e **non** nei file; se l'utente li vuole portabili serve la scrittura IPTC (fase di crescita). Rischio da dichiarare in interfaccia.
- **ADR-004 — Quasi-duplicati tramite feature print di Vision, non hash percettivo artigianale.** *Decisione:* distanza tra embedding di sistema, combinata alla vicinanza temporale EXIF. *Motivo:* qualità molto superiore a un hash percettivo su ritagli, esposizioni e piccoli movimenti, con costo computazionale sul Neural Engine. *Conseguenza:* la soglia non ha un significato assoluto e va calibrata: deve essere regolabile con anteprima visiva immediata dei gruppi.
- **ADR-005 — Distribuzione personale senza sandbox.** *Decisione:* `.dmg` notarizzato con hardened runtime, senza App Sandbox, con Accesso completo al disco. *Motivo:* le operazioni massive su cartelle arbitrarie e volumi esterni sono il cuore dell'app e la sandbox le renderebbe attritose. *Conseguenza:* la distribuzione a terzi e il Mac App Store restano fuori portata fino all'introduzione della sandbox; l'accesso al filesystem va comunque incapsulato in un unico livello, così che introdurre i bookmark con ambito di sicurezza in seguito sia un cambiamento locale.
- **ADR-006 — Il modello estetico gira solo su richiesta, e solo dentro un gruppo già formato.** *Decisione:* mai in scansione di cartella; ingresso della pipeline già ridotto a pochi candidati. *Motivo:* protegge il vincolo di latenza, che è il rischio primario. *Conseguenza:* il punteggio estetico non è disponibile come criterio di ordinamento globale, e non lo sarà finché non esistono prove di prestazione che lo permettano.
- **ADR-007 — Reversibilità per costruzione: dry-run, journal, Cestino.** *Decisione:* nessuna operazione massiva viene eseguita senza anteprima; ogni lotto è registrato in un journal persistente; le eliminazioni passano dal Cestino di macOS. *Motivo:* la funzione più utile è anche la più pericolosa, e la fiducia è un requisito di prodotto. *Conseguenza:* il journal è parte dello schema SQLite dal primo giorno e ogni operazione di `FileOps` deve essere modellata come lotto descrivibile e invertibile.
- **ADR-008 — `NSCollectionView` per la griglia, SwiftUI per tutto il resto.** *Decisione:* ponte AppKit limitato alla griglia. *Motivo:* riuso di celle e fluidità su decine di migliaia di elementi. *Conseguenza:* una superficie di codice AppKit da mantenere, confinata a un solo componente con contratto esplicito verso il resto.
- **ADR-009 — Scheduler con code delimitate e cancellazione obbligatoria.** *Decisione:* ogni lavoro asincrono (anteprime, metadati, hash, Vision) passa da uno scheduler con parallelismo limitato ai core disponibili, priorità alle celle visibili e cancellazione immediata di ciò che esce dallo schermo. *Motivo:* è la mitigazione diretta dell'anti-pattern individuato nell'anti-problem. *Conseguenza:* nessun componente ha licenza di avviare lavoro "al volo" fuori dallo scheduler.
- **ADR-010 — Le regole sono dati, non codice.** *Decisione:* pattern di rinomina e regole di smistamento sono modellati come strutture serializzabili con una grammatica dichiarata. *Motivo:* rende possibili preset, condivisione e cartelle intelligenti in seguito senza riscrivere il motore. *Conseguenza:* la grammatica dei token va specificata e versionata (vedi requisiti funzionali FR-020/FR-021).

---

## Functional Requirements

### Area 1 - Navigazione e apertura delle cartelle

- **FR-001** L'utente può aprire una cartella trascinandola sull'app o sulla sua icona, tramite il dialogo di apertura di sistema, dalle cartelle recenti o dai preferiti nella barra laterale.
- **FR-002** La vista mostra **esclusivamente** i file riconosciuti come immagini secondo il tipo di sistema (`UTType`), non secondo l'estensione. Nessun altro tipo di file è visibile in griglia.
- **FR-003** L'app indica quanti elementi non-immagine sono presenti nella cartella, senza mescolarli mai al contenuto visibile.
- **FR-004** L'utente può ordinare per nome, data di scatto, data di modifica, dimensione file e rating, in ordine crescente o decrescente, e l'ordinamento scelto persiste tra le sessioni.
- **FR-005** L'app rileva le modifiche alla cartella aperta (file aggiunti, rimossi, rinominati, modificati da altre applicazioni) e aggiorna la vista senza intervento dell'utente e senza perdere la selezione corrente.
- **FR-006** L'app ricorda le cartelle aperte di recente e permette all'utente di fissare cartelle preferite nella barra laterale.

### Area 2 - Visualizzazione

- **FR-007** La griglia mostra le anteprime con dimensione della cella regolabile su almeno cinque livelli, fino a una dimensione che permetta di valutare la nitidezza senza aprire l'immagine.
- **FR-008** La griglia resta fluida durante lo scorrimento su cartelle di almeno 10.000 immagini, caricando le anteprime delle sole celle visibili e annullando il lavoro non più necessario.
- **FR-009** L'utente può aprire un'anteprima grande dell'immagine selezionata, a pannello o a schermo intero, con un solo tasto.
- **FR-010** Nell'anteprima grande l'utente può ingrandire fino alla scala 1:1 dei pixel e spostarsi nell'immagine, per valutare fuoco e dettaglio.
- **FR-011** Le immagini sono visualizzate rispettando l'orientamento EXIF e il profilo colore incorporato.
- **FR-012** L'app segnala visivamente le immagini per le quali non è possibile generare un'anteprima o leggere il contenuto, senza interrompere il caricamento delle altre.

### Area 3 - Navigazione da tastiera

- **FR-013** L'utente può spostare la selezione tra le immagini con i soli tasti freccia, sia in griglia (movimento bidimensionale) sia in anteprima grande (immagine precedente e successiva).
- **FR-014** L'utente può estendere la selezione da tastiera (freccia con modificatore), selezionare tutto e invertire la selezione.
- **FR-015** Tutte le azioni dell'MVP — anteprima grande, pannello metadati, rating, marcatura, spostamento nel Cestino, rinomina, avvio dell'analisi di selezione — sono attivabili da tastiera senza usare il mouse.
- **FR-016** L'app espone un pannello di aiuto che elenca tutte le scorciatoie attive, richiamabile con un tasto.

### Area 4 - Metadati

- **FR-017** Un pannello metadati, mostrabile e nascondibile con un tasto, presenta per l'immagine selezionata: nome e percorso, dimensione del file, dimensioni in pixel, formato, data di creazione e di modifica, spazio colore.
- **FR-018** Lo stesso pannello mostra i dati EXIF disponibili — fotocamera, obiettivo, ISO, tempo di esposizione, diaframma, lunghezza focale, data e ora di scatto, orientamento — e i dati IPTC e GPS quando presenti, indicando esplicitamente i campi assenti anziché ometterli silenziosamente.
- **FR-019** Il pannello si aggiorna al cambio di selezione senza latenza percepibile; con selezione multipla mostra i valori comuni e segnala i campi divergenti. L'utente può copiare il valore di un singolo campo o l'intero blocco di metadati.

### Area 5 - Rinomina massiva (capacità a)

- **FR-020** L'utente può rinominare una selezione di immagini applicando un pattern composto da testo libero e token. I token supportati nell'MVP sono almeno:

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

- **FR-021** L'app mostra **obbligatoriamente** un'anteprima `nome attuale → nome nuovo` per ogni file coinvolto prima di eseguire qualsiasi rinomina, evidenziando collisioni, caratteri non ammessi dal filesystem, nomi troppo lunghi e ricadute su dati mancanti.
- **FR-022** L'utente sceglie esplicitamente la politica per le collisioni: aggiungere un suffisso progressivo, saltare il file, oppure annullare l'intero lotto. Il valore predefinito non sovrascrive mai un file esistente.
- **FR-023** L'estensione originale del file è preservata e non è modificabile dal pattern.
- **FR-024** Ogni lotto di rinomina è registrato in un journal persistente e può essere annullato integralmente anche dopo la chiusura e riapertura dell'app, purché i file coinvolti non siano stati modificati nel frattempo; in caso di modifiche l'annullamento è parziale e l'app riporta esattamente cosa non ha potuto ripristinare.

### Area 6 - Smistamento in sottocartelle (capacità b)

- **FR-025** L'utente può generare automaticamente sottocartelle e spostarvi le immagini secondo una regola scelta tra: data di scatto (con granularità anno, anno-mese, anno-mese-giorno), fotocamera, formato del file, rating, marcatura da scartare.
- **FR-026** Il nome delle sottocartelle generate è definibile con la stessa grammatica di token della rinomina massiva.
- **FR-027** L'app mostra obbligatoriamente l'anteprima dell'albero risultante — quali cartelle verranno create e quanti file finiranno in ciascuna — prima di eseguire qualsiasi spostamento.
- **FR-028** Le immagini per le quali la regola non è applicabile (dato mancante) finiscono in una cartella di raccolta con nome configurabile, e non vengono mai lasciate in uno stato indeterminato.
- **FR-029** Anche lo smistamento è registrato nel journal e annullabile con lo stesso contratto della rinomina (FR-024).
- **FR-030** Nell'MVP le operazioni massive agiscono sulla cartella corrente e non discendono ricorsivamente nelle sottocartelle; questo limite è dichiarato in interfaccia.

### Area 7 - Giudizio, marcatura e filtri

- **FR-031** L'utente può assegnare un rating da 1 a 5 stelle, rimuoverlo, e marcare o smarcare un'immagine come "da scartare", con un singolo tasto e senza lasciare la posizione corrente.
- **FR-032** Rating e marcature sono salvati nell'indice locale, sopravvivono al riavvio e seguono il file quando questo viene rinominato o spostato tramite l'app.
- **FR-033** L'utente può filtrare la vista per rating (minimo, esatto), per marcatura, per formato e per intervallo di date, e combinare i filtri.
- **FR-034** L'interfaccia dichiara che rating e marcature vivono nell'indice locale e non dentro i file, così che l'utente sappia cosa succede se l'indice viene eliminato o se i file vengono spostati da un'altra applicazione.

### Area 8 - Duplicati

- **FR-035** L'app individua i **duplicati esatti** (contenuto byte-identico, anche con nome diverso) all'interno della selezione o della cartella corrente, procedendo per stadi di costo crescente e senza leggere integralmente file che possono essere esclusi prima.
- **FR-036** I duplicati esatti sono presentati in gruppi con un candidato da tenere proposto secondo criteri dichiarati (percorso più stabile, nome più informativo, data più antica), sempre modificabile dall'utente.
- **FR-037** L'app individua i **gruppi di quasi-duplicati** combinando similarità visiva e vicinanza temporale di scatto, con soglia regolabile e riorganizzazione visiva immediata dei gruppi al variare della soglia.
- **FR-038** Nessun duplicato, esatto o approssimato, viene eliminato senza conferma esplicita dell'utente; l'eliminazione passa dal Cestino di macOS.

### Area 9 - Selezione assistita (capacità c)

- **FR-039** Data una selezione di immagini, l'utente può chiedere all'app di proporre le **N migliori da tenere** (N predefinito 3, regolabile almeno tra 1 e 10).
- **FR-040** L'analisi procede nell'ordine di priorità stabilito: (1) raggruppamento per similarità visiva e temporale, (2) valutazione del soggetto — volti rilevati, qualità del volto, occhi aperti o chiusi, (3) qualità tecnica misurabile — nitidezza valutata sul soggetto e non sull'intero fotogramma, mosso, esposizione e clipping, rumore stimato, (4) punteggio estetico come criterio di spareggio finale.
- **FR-041** Per **ogni** immagine valutata l'app mostra il punteggio scomposto nei criteri che lo compongono, in forma leggibile ("a fuoco: alto — 2 volti, occhi aperti — esposizione corretta"), e non un singolo numero opaco.
- **FR-042** L'app dichiara sempre **perché** un'immagine è stata proposta e perché un'altra è stata scartata, in termini di criteri, così che l'utente possa dissentire con cognizione.
- **FR-043** L'utente può modificare la proposta prima di agire (aggiungere o togliere immagini dai "da tenere"), e nessuna immagine viene eliminata o spostata senza una conferma esplicita.
- **FR-044** L'analisi è eseguita **solo su richiesta e solo su una selezione**: aprire una cartella non innesca in nessun caso il calcolo dei punteggi di qualità o del punteggio estetico.
- **FR-045** L'analisi è annullabile in qualunque momento, mostra un avanzamento leggibile, e i risultati parziali già calcolati restano validi e memorizzati.
- **FR-046** Tutta l'analisi avviene in locale: nessuna immagine, nessun dato derivato e nessun metadato lascia il dispositivo in nessuna circostanza.

### Area 10 - Editing di base

- **FR-047** L'utente può ruotare un'immagine di 90° in entrambi i versi e capovolgerla orizzontalmente e verticalmente, anche su selezioni multiple.
- **FR-048** L'utente può ritagliare un'immagine con proporzioni libere o predefinite (1:1, 4:3, 3:2, 16:9), con riquadro trascinabile e valori visibili.
- **FR-049** Al salvataggio l'utente sceglie esplicitamente tra sovrascrivere l'originale e creare una copia; l'opzione predefinita è la copia.
- **FR-050** Il salvataggio preserva i metadati EXIF/IPTC dell'immagine di partenza, aggiornando i soli campi resi incoerenti dalla trasformazione (dimensioni, orientamento).

### Area 11 - Operazioni su file e reversibilità

- **FR-051** L'utente può spostare, copiare e rinominare singole immagini e selezioni verso una cartella di destinazione scelta, con gestione esplicita delle collisioni.
- **FR-052** L'eliminazione avviene **sempre** tramite il Cestino di macOS e mai con una cancellazione diretta.
- **FR-053** L'app espone una cronologia delle operazioni massive eseguite, con la possibilità di annullare un lotto specifico e non solo l'ultimo.
- **FR-054** Ogni operazione su file riporta un esito esplicito: quanti file elaborati, quanti saltati, quanti in errore e per quale motivo. Un errore su un singolo file non interrompe il lotto né lo lascia in stato indeterminato.
- **FR-055** L'utente può rivelare qualsiasi immagine nel Finder e aprirla con un'altra applicazione, senza perdere lo stato dell'app.

### Area 12 - Indice locale e prestazioni

- **FR-056** L'app mantiene un indice locale di metadati, hash, dati di similarità, rating e marcature, chiavato sull'identità del file (volume, inode, dimensione, data di modifica), e non ricalcola ciò che è già valido.
- **FR-057** L'indice è integralmente ricostruibile: l'utente può svuotarlo dalle impostazioni senza perdere nessuna immagine e senza rendere l'app inutilizzabile. La perdita di rating e marcature è dichiarata prima dell'operazione.
- **FR-058** Alla riapertura di una cartella già indicizzata, la griglia è popolata dalla cache senza ricalcoli.

### Area 13 - Accessibilità

- **FR-059** Ogni funzione dell'MVP è raggiungibile da tastiera; nessuna azione richiede esclusivamente il mouse o il trackpad.
- **FR-060** Le immagini in griglia, i controlli e i campi del pannello metadati espongono etichette leggibili da VoiceOver; il valore dei metadati è annunciabile senza aprire finestre aggiuntive.
- **FR-061** L'app rispetta le preferenze di sistema *Riduci movimento* e *Aumenta contrasto*, e supporta la dimensione del testo di sistema nei pannelli senza troncamenti.

---

## Non-Functional Requirements

### Prestazioni e reattività

Sono i requisiti che governano il rischio primario del prodotto e vanno trattati come vincoli, non come obiettivi:

- **NFR-P1** Alla prima apertura di una cartella con 3.000 immagini, la prima schermata di anteprime è visibile entro **1 secondo**; la griglia è navigabile mentre il resto continua a caricarsi in sottofondo.
- **NFR-P2** Alla riapertura di una cartella già indicizzata la griglia è popolata **immediatamente** dalla cache, senza alcun ricalcolo.
- **NFR-P3** Lo spostamento della selezione con le frecce risponde entro **100 ms** anche mentre sono in corso lavori in sottofondo; l'interfaccia non si blocca mai, in nessuna operazione.
- **NFR-P4** Il pannello metadati si aggiorna entro **150 ms** dal cambio di selezione.
- **NFR-P5** Nessuna scansione bloccante all'apertura di una cartella: enumerazione, metadati, hash e analisi visiva sono lavori annullabili a priorità inferiore all'interazione.
- **NFR-P6** Il lavoro in sottofondo relativo a celle uscite dallo schermo è annullato immediatamente; la coda non cresce indefinitamente con lo scorrimento.
- **NFR-P7** L'occupazione di memoria resta stabile su cartelle da 10.000 immagini: le anteprime sono liberate al di fuori della finestra di visualizzazione.
- **NFR-P8** Il rilevamento dei duplicati esatti su 10.000 file non legge integralmente i file che possono essere esclusi negli stadi precedenti.

### Affidabilità e integrità dei dati

- **NFR-A1** Nessuna operazione distruttiva senza conferma esplicita; nessuna eliminazione fuori dal Cestino di macOS.
- **NFR-A2** Ogni operazione massiva è preceduta da un'anteprima completa dell'effetto e registrata in un journal persistente che ne consente l'annullamento dopo il riavvio.
- **NFR-A3** L'interruzione dell'app durante un lotto non lascia il filesystem in stato incoerente: il journal permette di riconoscere e riportare esattamente lo stato raggiunto.
- **NFR-A4** L'app non modifica mai un file che l'utente non ha esplicitamente incluso in un'operazione.
- **NFR-A5** Un file corrotto o illeggibile non compromette il caricamento della cartella né di alcuna operazione sugli altri file.

### Sicurezza

- **NFR-S1 Nessuna rete a tempo di esecuzione.** L'app non invia immagini, metadati, dati derivati né telemetria a nessun servizio remoto, in nessuna circostanza. L'unica connessione ammessa è l'eventuale download iniziale del modello estetico, se si scegliesse di non includerlo nel bundle: sarebbe esplicita, verso un'origine dichiarata, verificata per integrità e completamente rinunciabile.
- **NFR-S2 Nessun account, nessuna credenziale, nessun dato personale raccolto.** Non esiste autenticazione perché non esiste nulla da autenticare.
- **NFR-S3 Distribuzione firmata.** Binario firmato con hardened runtime e notarizzato da Apple; nessuna disattivazione di Gatekeeper richiesta all'utente.
- **NFR-S4 Ambito dell'accesso al filesystem.** L'app opera senza sandbox, con Accesso completo al disco concesso dall'utente. Per compensare l'ampiezza del permesso: tutte le scritture passano da un unico livello di accesso al filesystem, che è il solo punto in cui il codice può modificare o eliminare qualcosa, ed è coperto da test dedicati. Questo livello è anche il punto d'innesto per la futura sandbox.
- **NFR-S5 Dati sensibili nei metadati.** Le coordinate GPS sono trattate come informazione sensibile: mostrate su richiesta, mai incluse in nomi di file generati automaticamente, e rimovibili in esportazione (fase di crescita).
- **NFR-S6 Superficie delle dipendenze ridotta al minimo.** L'unica dipendenza esterna a tempo di esecuzione è GRDB.swift; tutto il resto è framework di sistema. Ogni nuova dipendenza richiede una decisione architetturale registrata.
- **NFR-S7 Provenienza del modello.** Il modello estetico open source è versionato, la sua licenza è verificata come compatibile con la distribuzione, e la sua origine e conversione sono documentate nel repository.

### Integrazioni

Tutte le integrazioni sono con il sistema operativo; non esiste alcuna integrazione con servizi di terze parti.

- **NFR-I1 QuickLook Thumbnailing** — generazione delle anteprime per tutti i formati supportati dal sistema, con riuso della cache di sistema.
- **NFR-I2 ImageIO** — lettura di metadati EXIF/IPTC/GPS/TIFF, decodifica ridimensionata, scrittura in fase di salvataggio con preservazione dei metadati.
- **NFR-I3 Vision** — feature print dell'immagine per la similarità visiva, rilevamento volti, qualità di cattura del volto, landmark oculari.
- **NFR-I4 Core ML** — esecuzione locale del modello estetico open source, su richiesta e su insiemi già ridotti.
- **NFR-I5 Core Image e Metal** — trasformazioni geometriche, istogrammi, misure di nitidezza, con accelerazione GPU.
- **NFR-I6 File System Events** — rilevamento delle modifiche alla cartella aperta.
- **NFR-I7 Cestino di macOS** — unica via di eliminazione, con ripristino garantito dal sistema.
- **NFR-I8 Servizi Finder** — rivela nel Finder, apri con, foglio di condivisione di sistema.
- **NFR-I9 Accessibilità di sistema** — VoiceOver, *Riduci movimento*, *Aumenta contrasto*, dimensione del testo.
- **NFR-I10 Nessuna integrazione con la libreria Foto di macOS** nell'MVP: scelta esplicita coerente con "la cartella è la fonte di verità".

---

## Next Steps

1. **Backlog** - Esegui `/archetipo-spec` per trasformare questo PRD in un backlog
2. **Design** - Esegui `/archetipo-design` per i mockup dell'interfaccia (quando applicabile)
3. **Validazione** - Rivedi con gli stakeholder e metti alla prova gli assunti più rischiosi

---

_PRD generato tramite ARchetipo Product Inception - 2026-08-24_
_Sessione condotta da: alessandro.giardina@intre.it con il team ARchetipo_
