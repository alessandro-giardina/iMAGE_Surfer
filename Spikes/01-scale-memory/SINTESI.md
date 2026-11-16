# Cancello n°1 — Sintesi in linguaggio semplice

Questa è una sintesi divulgativa di due documenti tecnici:

- [`RESULT.md`](RESULT.md), l'esito completo del cancello n°1, con tutte le misure;
- [Ammissione del lavoro con stime calibrate e banda di ritenzione](../../docs/wiki/decisions/work-admission-budget.md), la pagina Wiki con la regola di funzionamento che ne deriva.

Le cifre qui sono arrotondate. I valori esatti, la loro origine e i limiti della misura sono nei due documenti originali, che restano il riferimento.

## A cosa serviva il test

Il PRD contiene alcune promesse sulle prestazioni: aprire in fretta una cartella grande, tenere la memoria sotto controllo, non bloccare l'interfaccia mentre l'app lavora in sottofondo. Erano promesse scritte a tavolino. Il cancello n°1 serviva a verificarle con misure reali su una cartella da 50.000 immagini, prima di scrivere il codice dell'app.

Per farlo è stato costruito un piccolo programma di prova, da buttare dopo l'uso. Riproduce le parti critiche dell'app: la griglia di anteprime, lo scorrimento e il lavoro in sottofondo. Tutte le misure sono state fatte su un MacBook Pro M1 Pro con 32 GB.

Ogni promessa ha avuto uno di due esiti:

- **confermata**: regge così com'è scritta;
- **emendata**: va riscritta con numeri veri o con delle precisazioni.

Il PRD non è stato modificato. I testi corretti da sostituire sono pronti in `RESULT.md`, sezione *Esito*.

## I quattro risultati

### 1. La prima schermata appare in meno di mezzo secondo, ma solo con il metodo giusto (NFR-P1: confermato)

La promessa: aprendo una cartella di 3.000 immagini, le prime anteprime compaiono entro 1 secondo.

macOS offre due modi per creare le anteprime:

- **Quick Look**, il servizio di sistema usato dal Finder: di solito circa 0,9 s, ma nei casi peggiori fino a 1,8 s. **Non basta.**
- **ImageIO**, con cui l'app legge il file e lo rimpicciolisce da sé: circa 0,4 s, al massimo 0,45 s. **Ampiamente dentro.**

Quindi l'app dovrà usare ImageIO per la griglia.

Anche la navigazione con le frecce resta istantanea: meno di 3 millesimi di secondo, con il computer al lavoro a pieno ritmo in sottofondo.

### 2. La memoria è contenuta, ma cresce un po' nel tempo (NFR-P9: emendato)

Il PRD chiedeva due cose: un tetto massimo di memoria e nessuna crescita nelle sessioni lunghe.

- **Tetto: regge.** Scorrendo tutte le 50.000 immagini avanti e indietro, il picco massimo è stato 373 MB. Con un margine di sicurezza del 50% il tetto proposto è **560 MB**.
- **Nessuna crescita: non regge.** In un'ora di uso la memoria oscilla, ma tende a salire di circa **7 MB all'ora**. È poco, ma la crescita è reale e non un errore di misura: anche nella stima più favorevole resta sopra zero. Da dove venga non è stato scoperto.

La promessa «la memoria non cresce» è quindi registrata come **non mantenibile**. La proposta è sostituirla con «cresce al massimo di 16 MB all'ora». È l'unica promessa del PRD che non ha retto.

### 3. Quanto costa ogni immagine, e la sorpresa sui pixel (NFR-P10: emendato)

Su ogni immagine l'app farà lavori diversi:

- leggerla dal disco;
- crearne l'anteprima;
- analizzarla con la visione artificiale (volti, somiglianze);
- salvare l'anteprima nella cache.

Per ogni lavoro è stata misurata la memoria consumata, combinando formato (JPEG, HEIC, PNG, TIFF) e dimensione dell'immagine (piccola, media, grande, enorme). In tutto 65 combinazioni, quasi tutte misurate 20 volte.

- **Lettura dal disco:** costa quasi niente.
- **Anteprima:** da 0,7 a 4 MB.
- **Analisi visiva:** da 2 a 4 MB, ma su un'immagine enorme (192 megapixel) arriva a 13 MB.
- **La sorpresa:** per l'anteprima, un'immagine più grande non costa di più. Un JPEG piccolo costa più di uno medio, e un TIFF da 192 megapixel costa quanto uno da 48. Dalle dimensioni non si può quindi stimare la memoria: va misurata formato per formato. Solo l'analisi visiva cresce davvero con la dimensione.

La regola «stima più 50% di margine» funziona in 63 combinazioni su 65. Le due che sforano sono di analisi visiva. La causa è un costo fisso del sistema di visione: una sola volta occupa circa 17 MB in più e non li rilascia. La soluzione è tenere da parte 17 MB fissi per la visione, una volta sola.

### 4. L'architettura del lavoro in sottofondo (ADR-009: emendato)

ADR-009 descrive come l'app organizza il lavoro in sottofondo. L'idea di fondo regge. È emendato perché ora ha numeri veri e alcune precisazioni: ImageIO, la riserva fissa e il modo di riconoscere un'immagine anomala. È l'argomento della sezione seguente.

## La regola di funzionamento che ne deriva

La pagina Wiki sull'ammissione del lavoro trasforma le misure in regole per l'app.

**Code separate, budget comune.** L'app non fa tutto insieme. C'è una coda per ogni tipo di lavoro: disco, anteprime, visione e cache. Tutte attingono a un unico budget di memoria, come più reparti che condividono lo stesso conto spese.

**Prima stima, poi esegue.** Prima di avviare un lavoro l'app deve sapere se c'è memoria sufficiente, quindi deve stimare quanto costerà. Le stime vengono dalla tabella delle 65 combinazioni misurate. Non si usa la media ma un valore prudente: quello che copre 95 casi su 100. A questo si aggiunge il 50% di margine.

**Un limite per la singola immagine.** Se un'immagine si rivela molto più pesante del previsto, l'app interrompe solo quella e non va in crisi tutta. A seconda della combinazione, il limite va da 1 a 60 MB.

**Il cuscinetto attorno alla parte visibile.** L'app tiene in memoria le anteprime visibili più un piccolo margine sopra e sotto, così scorrendo un po' le si trova già pronte.

Se però un'anteprima viene buttata appena esce dal margine e si torna indietro di poco, va ricreata. Scorrendo avanti e indietro, l'app rifarebbe continuamente lo stesso lavoro.

La soluzione è usare due soglie diverse, come un termostato che accende a 19° e spegne a 21° invece di scattare di continuo attorno ai 20°:

- un'anteprima viene **caricata** quando arriva a mezza schermata dalla parte visibile;
- viene **scartata** solo quando si allontana di una schermata intera.

Risultato misurato su un piccolo movimento avanti e indietro: con due soglie l'app rifà **0 anteprime**, con una sola soglia ne rifà **228**. Il cuscinetto costa circa **33 MB**, cioè 48 anteprime tenute in memoria.

## Avvertenze

- **Hardware.** Il Mac di misura ha 32 GB, ma il Mac più piccolo da supportare ne ha 8. Per coprire la differenza è stato aggiunto un altro 50% di margine. È un'ipotesi, non una misura: va verificata appena sarà disponibile un Mac da 8 GB.
- **Immagini finte.** Le 50.000 immagini sono generate dal programma e non contengono volti. Su foto vere l'analisi dei volti costerà di più.
- **Quick Look non è misurabile.** Lavora in un processo separato del sistema, quindi la sua memoria non si vede.
- **Tre punti misurati ma non spiegati:**
  - la crescita di circa 7 MB all'ora;
  - circa 0,7 MB che restano in memoria dopo ogni salvataggio nella cache;
  - i 17 MB che la visione trattiene.

## In sintesi

L'app può aprire cartelle molto grandi in fretta e con la memoria sotto controllo, a tre condizioni:

- usare ImageIO per le anteprime;
- stimare i costi per formato e non per dimensione;
- tenere attorno alla parte visibile un cuscinetto a due soglie.

L'unica promessa da ammorbidire è «la memoria non cresce mai»: cresce poco, e va tenuta sotto 16 MB all'ora.
