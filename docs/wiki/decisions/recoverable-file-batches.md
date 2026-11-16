---
type: decision
title: Lotti di operazioni su file recuperabili con esiti dichiarati
description: ADR-007 emendato dal cancello n°4; lotti recuperabili e non atomici con sei esiti dichiarati, i cinque del PRD con «compensato» ridefinito più «interrotto prima di agire», ed errori classificati per ambito, con tre classi sistemiche che sospendono il lotto e cinque locali che fanno saltare il file
status: reviewed
decision_status: accepted
sources:
    - path: Spikes/04-crash-recovery/RESULT.md
      role: verification
    - path: Spikes/04-crash-recovery/measurements/crash-matrix-20261116T154019Z-0eefc599.json
      role: verification
    - path: Spikes/04-crash-recovery/Sources/CrashKit/OutcomeClassifier.swift
      role: implementation
    - path: Spikes/04-crash-recovery/Sources/CrashKit/ErrorClassifier.swift
      role: implementation
review:
    content_hash: sha256:fecc2e8ce0a9ec6b2063f2ecace0184d4a3212427833d879b5b694cc0296e82a
    evidence_revision: 10ec6ad380b970b8afee728ac05a08f63794c9a4
    evidence_hash: sha256:33489aee09a3c6fd97f95cfc17f080f49753d9a636b8ad72105b263dc90a1729
    reviewed_at: "2026-11-16T22:17:56Z"
---
# Lotti di operazioni su file recuperabili con esiti dichiarati

Questa pagina registra la semantica di recupero dei lotti di operazioni su file di iMAGE Surfer come chiusa dal cancello tecnico n°4. La fonte di ogni esito, conteggio e scostamento è `Spikes/04-crash-recovery/RESULT.md`, che li riconduce alla misura versionata `crash-matrix-20261116T154019Z-0eefc599`. Ogni esito qui riportato vale per la configurazione dichiarata in § *Configurazione* di quel documento: un volume APFS locale su immagine disco (`CrashBench`, immagine ASIF da 64 MB) e l'arresto del processo per `SIGKILL`, su MacBookPro18,3 con macOS 27.2, build 26B123, con 5 ripetizioni per cella.

<!-- archetipo:wiki section=context -->

## Contesto

Le forze che la decisione deve tenere insieme:

- **Il filesystem non offre transazioni su più file.** Un lotto che rinomina, sposta, copia e manda nel Cestino molti file non può essere reso indivisibile. Fra un passo e l'altro, e fra un'azione e la sua registrazione, esiste sempre uno stato intermedio che un arresto può fissare sul disco. Il registro può rendere un lotto **recuperabile**, non atomico.
- **ADR-007 era provvisorio.** ADR-015 dichiarava formalmente provvisori gli ADR-007, 009, 011, 012 e 013 fino all'esito scritto del cancello tecnico corrispondente. Per ADR-007 è il cancello n°4, l'iniezione di arresti in ogni punto di un lotto (vedi [Mappa dei contesti](/architecture/context-map.md)).
- **I cinque esiti erano dichiarati, non misurati.** La revisione 1.3 del PRD aveva sostituito l'esito binario «ripreso o compensato» della 1.2 con cinque esiti: completato, compensato, parzialmente recuperato, bloccato in attesa dell'utente, abbandonato dall'utente. Nessuna misura diceva da quali punti di interruzione si raggiunge ciascuno, se la compensazione riporta lo stato precedente e quali casi finiscono legittimamente in «bloccato».
- **«Bloccato in attesa dell'utente» richiede che l'utente lo sappia.** Un esito che sospende il lotto fa parte dell'interfaccia, non del registro interno. Va quindi riservato ai casi che solo l'utente può sbloccare, e la distinzione fra errore locale ed errore sistemico va decisa per ogni classe di errore.

Il cancello n°4 ha registrato ADR-007 come **emendato**. La semantica descritta qui **sostituisce** la formulazione di ADR-007 nel PRD 1.3 (`docs/PRD.md`, riga 530). Il testo di sostituzione completo è in `RESULT.md` § *Esito su ADR-007*, sotto *Testo di sostituzione*, e il PRD non è stato modificato. Le differenze rispetto al PRD sono tre:

- gli esiti sono sei e non cinque: si aggiunge **interrotto prima di agire**;
- «compensato» significa che ogni passo eseguito è stato riportato all'origine, **non** che il disco coincida con lo stato di partenza;
- il file modificato dall'esterno e il Cestino svuotato sono errori locali su un solo file, non situazioni in cui né la ripresa né la compensazione sono possibili.

Regge invece il resto di ADR-007: il log di intenti scritto prima dell'azione, il ricontrollo delle precondizioni, i passi idempotenti, la sospensione del lotto sull'errore sistemico e il passaggio delle eliminazioni dal Cestino. La frase «il registro vive in `DurableState`» resta quella del PRD, e questo cancello non la verifica.

<!-- archetipo:wiki section=decision -->

## Decisione

Un lotto di operazioni su file è una macchina a stati con log di intenti scritto **prima** dell'azione. Il piano viene registrato, le precondizioni ricontrollate immediatamente prima di agire, il lotto preparato, e i passi idempotenti eseguiti e registrati uno a uno. Dopo un arresto il recupero riconosce **dal disco** lo stato di ogni file, procede nella direzione stabilita e conclude in uno di **sei esiti dichiarati**.

La misura che fissa i valori seguenti copre 61 punti di interruzione e 146 celle, cioè 98 di base e 48 di perturbazione, di cui 129 applicabili. Con 5 ripetizioni per cella dà 645 ripetizioni con esito, senza alcuna cella `PUNTO_NON_RAGGIUNTO`, `RICONOSCIMENTO_ERRATO` o non deterministica.

### Insieme degli esiti

| Esito | Definizione | Misura |
|---|---|---|
| completato | Ogni passo fatto nella direzione in avanti | 38 celle, 190 ripetizioni, più i rami `retry` delle celle bloccate in ripresa |
| compensato | Ogni passo eseguito riportato all'origine. Lo stato può differire da quello di partenza, e gli scostamenti si dichiarano | 59 celle, 295 ripetizioni. Coincidono con lo stato di partenza solo `X01-plan/compensate` e `X02-recheck/compensate` |
| parzialmente recuperato | Almeno un file saltato per errore locale, il resto concluso | 17 celle, 85 ripetizioni, tutte con un errore locale |
| bloccato in attesa dell'utente | Un errore sistemico non risolto, incontrato da un passo | 13 celle, 65 ripetizioni, tutte con un errore sistemico |
| abbandonato dall'utente | Decisione dell'utente su un lotto bloccato. I file restano dove sono, e la loro posizione si riferisce | 65 rami `abandon` su 65 |
| interrotto prima di agire | Nessuna azione eseguita sul disco: il piano non è stato registrato per intero, oppure il ricontrollo ha trovato le precondizioni cambiate (FR-080). Non c'è nulla da riprendere né da compensare | `X00-plan-torn/resume` e `X00-plan-torn/compensate`: 10 ripetizioni su 10 `NON_SUPPORTABILE`, motivo `nessun-esito-applicabile`, nel banco a cinque esiti. L'interruzione di FR-080 non è raggiunta dalla matrice |

Da 60 dei 61 punti la strategia scelta conclude in 5 ripetizioni su 5: `completato` in ripresa, `compensato` in compensazione, in 96 celle di base. Uno stato non riconoscibile non entra nell'insieme: resta un esito non supportabile, dichiarato come tale e mai ricondotto a «bloccato». Nessuna cella della misura ha il motivo `stato-non-riconoscibile`.

### Classificazione degli errori per ambito

Il classificatore verifica nell'ordine il volume, la scrittura, lo spazio e infine le cause locali osservate sul disco. Decide la prima condizione che corrisponde, mai il solo errno. Un errore **sistemico** sospende il lotto al primo passo che lo incontra; un errore **locale** fa saltare il file, e il lotto prosegue.

| Classe | Ambito | Errore osservato | Celle provate | Esiti | Classificazione |
|---|---|---|---|---|---|
| `G-volume-missing` | sistemico | nessuna chiamata: il volume assente è riconosciuto prima di agire | 6 | `bloccato` 30/30 | confermata |
| `G-folder-readonly` | sistemico | `EACCES` (13) da `renamex_np`, `rmdir`, `copyfile` | 6 | `bloccato` 25/30, `completato` 5/30 | confermata. `S10-c/resume` conclude perché ogni passo è già fatto e nessuno incontra l'errore |
| `G-space-exhausted` | sistemico | `ENOSPC` (28) da `renamex_np`, `copyfile` | 2 | `bloccato` 10/10 | confermata. Lo spazio esaurito può colpire anche le rinomine, non solo le copie: misurato in una sola cella |
| `L-locked` | locale | `EPERM` (1) da `renamex_np`; errore Cocoa `NSCocoaErrorDomain` 513 / `NSOSStatusErrorDomain` -5000 da `trashItem`, senza errno | 4 | `parzialmente-recuperato` 20/20 | confermata |
| `L-collision` | locale | nessuna chiamata: riconosciuta dal disco prima di agire | 4 | `parzialmente-recuperato` 20/20 | confermata |
| `L-modified` | locale | nessuna chiamata: riconosciuta dal disco prima di agire | 4 | `parzialmente-recuperato` 20/20 | corretta in una cella: in `S10-c/compensate/L-modified` il recupero adotta `L-trash-emptied`, con lo stesso ambito e lo stesso esito |
| `L-trash-emptied` | locale | nessuna chiamata: riconosciuta dal disco prima di agire | 1 | `parzialmente-recuperato` 5/5 | confermata |
| `L-missing` | locale | nessuna chiamata: riconosciuta dal disco prima di agire | 4 | `parzialmente-recuperato` 20/20 | corretta in una cella: in `S10-c/compensate/L-missing` il recupero adotta `L-trash-emptied`, con lo stesso ambito e lo stesso esito |

L'ambito regge per tutte e otto le classi. Le due correzioni riguardano la classe, non l'ambito: sul disco una voce del Cestino modificata o sparita non si distingue da un Cestino svuotato, perché nessuna voce ha più il digest del piano. Le 17 celle applicabili con errore locale finiscono tutte `parzialmente-recuperato`, e nessuna `bloccato`. Ogni cella bloccata registra **al più un** fallimento, e nessuna lo ripete sui file restanti (FR-079).

### Punti legittimamente bloccati

Finiscono in «bloccato in attesa dell'utente» 13 celle, tutte sistemiche e tutte incontrate da un passo. Nessun errore locale e nessuno stato senza esito vi finisce. Dopo ogni blocco il banco ha provato i due rami dell'utente, 5 volte ciascuno.

| Classe | Celle | Ragione | Dopo `retry` | Dopo `abandon` |
|---|---|---|---|---|
| `G-volume-missing` | 6: `X03-prepare`, `S06-b` e `S10-c`, in ripresa e in compensazione | Il volume del lotto non c'è. Il recupero lo riconosce prima di agire e sospende ogni passo, perché né riprendere né compensare è possibile senza il volume; solo l'utente può ricollegarlo o rinunciare | nella direzione del log, 5/5 per cella | `abbandonato` 5/5 per cella |
| `G-folder-readonly` | 5: `X03-prepare/resume` (`S01`, `renamex_np`), `X03-prepare/compensate` (`rmdir` delle cartelle preparate), `S06-b/resume` (`S07`, `copyfile`), `S06-b/compensate` (`S06`, `renamex_np`), `S10-c/compensate` (`S10`, `renamex_np`) | Le cartelle del lotto non sono scrivibili. Il primo passo che deve scriverci fallisce con `EACCES`, e ogni passo restante fallirebbe allo stesso modo; solo l'utente può ripristinare il permesso | nella direzione del log, 5/5 per cella | `abbandonato` 5/5 per cella |
| `G-space-exhausted` | 2: `X03-prepare/resume` (`S01`, `renamex_np`), `S06-b/resume` (`S07`, `copyfile`) | Il volume è pieno. Il primo passo che deve occupare spazio fallisce con `ENOSPC`, e proseguire ripeterebbe il fallimento sui passi restanti; solo l'utente può liberare spazio | `completato` 5/5 per cella | `abbandonato` 5/5 per cella |

Rimossa la causa, `retry` conclude nella direzione del log: `completato` per le celle in ripresa, `compensato` per quelle in compensazione. `abandon` conclude `abbandonato` senza toccare i file, e riferisce dove è rimasto ciascuno. In nessun ramo `abandon` le posizioni riferite contraddicono l'istantanea del disco; l'esito dei rami `retry` è quello stampato dalla macchina, senza un oracolo sull'istantanea.

### Regole di riconoscimento

- **Il disco prevale sul log.** Il log dice che cosa si voleva fare, il disco che cosa è accaduto. In ogni punto `-b`, con l'azione eseguita e il fatto non registrato, il recupero riferisce `DIVERGENZA Sxx log=non-fatto disco=fatto`; nei punti `K*-b` riferisce `log=fatto disco=non-fatto`. In tutti decide dal disco e conclude come negli altri punti. Il lettore del log tollera un'ultima riga troncata: `S05-torn` riferisce `RECORD-TRONCATO si` e conclude in 5 ripetizioni su 5 con entrambe le strategie. In 146 celle non c'è alcun `RICONOSCIMENTO_ERRATO`.
- **Il Cestino si cerca per digest.** Nel Cestino il sistema può assegnare all'elemento un altro nome, e la sonda della baseline del piano ha osservato una collisione rinominata con un suffisso orario (`a.jpg 11-11-52-954.jpg`). La compensazione ritrova `OP5` nel Cestino per digest in ogni cella `compensato` in cui era già stato cestinato, e nel Cestino non ne resta traccia. Il prodotto può dire che un elemento non è più nel Cestino con il contenuto atteso, ma non perché.
- **Una compensazione avviata non si rovescia.** Quando il log registra una compensazione già avviata, la sua direzione prevale su quella chiesta, e il recupero non la rovescia in silenzio. È una regola del riconoscitore, **non** una misura: i punti `K*` si provano solo in compensazione, e nessuna cella prova il rovesciamento (`RESULT.md` § *Limiti dichiarati*, punto 10). La misura mostra soltanto che una compensazione arrestata due volte si conclude `compensato` (`D02/compensate`, 5 su 5).
- **Il volume si identifica dall'UUID.** Il piano registra l'UUID del volume. Il classificatore dichiara `G-volume-missing` se la radice del lotto manca o sta su un volume con un UUID diverso, e il passo Cestino rifiuta di agire su una sorgente fuori da quel volume. Il percorso non basta: la sonda della baseline ha mostrato che dopo l'espulsione il punto di montaggio resta come directory vuota del volume ospite. Con il volume assente il recupero non tenta alcun passo e li sospende tutti e dieci, e le 6 celle finiscono `bloccato` in 30 ripetizioni su 30.
- **La separazione di una coppia si riferisce.** Il recupero riferisce le coppie immagine-sidecar separate all'avvio e quelle residue. Delle 53 celle con coppie separate, tutte `rilevata`, le 44 di base si ricompongono e le 9 di perturbazione restano separate. In 8 celle è il salto per errore locale a separare una coppia che all'avvio era unita, e il recupero lo riferisce in `SEPARAZIONI-RESIDUE`.

### Scostamenti che una compensazione lascia

Una compensazione corretta riporta all'origine ogni immagine e ogni sidecar con il digest del piano, senza scostamenti di contenuto, inode o `birthtime` sui file del lotto, e senza traccia di `IMG_0005` nel Cestino. Lascia però questi scostamenti, che vanno dichiarati all'utente:

- **L'`mtime` della cartella del lotto**, in tutte le 57 celle `compensato` che non coincidono con lo stato di partenza, e in 72 delle 74 righe di compensazione. La preparazione crea `selezione/` e `consegna/`, e la compensazione le rimuove con `rmdir`: il contenuto torna quello di partenza, l'`mtime` no. In 23 celle è l'unico scostamento.
- **Le copie annullate nel Cestino.** Compensare la copia `OP4` significa spostarla nel Cestino, perché NFR-A1 vieta le eliminazioni dirette. `@cestino/IMG_0004.jpg` e `@cestino/IMG_0004.xmp` restano in 34 celle `compensato`. Solo il `.jpg` resta in `S07-b`, `S07-c`, `S08-a` e `S08-m`, dove la copia del sidecar non era ancora pubblicata.
- **`.DS_Store` creato dal sistema nel Cestino** alla prima voce, con `size` e `mtime` della cartella del Cestino cambiati, nelle stesse 34 celle.
- **In un annullamento parziale, ogni file non riportato**, con percorso e motivo. Per esempio in `S06-b/compensate/L-locked` il sidecar di `OP3` resta in `selezione/`, e la cartella, non vuota, non si rimuove.

<!-- archetipo:wiki section=alternatives -->

## Alternative valutate

- **Lotto atomico.** È scartato perché impossibile: il filesystem non offre una transazione su più file, e nessun registro rende indivisibile un lotto. La misura mostra proprio gli stati intermedi che un'unità atomica dovrebbe escludere. In 44 celle di base l'istantanea presa all'arresto ha un'immagine e il suo sidecar in posizioni diverse, e in ogni punto `-b` l'azione è già sul disco mentre il log non la registra.
- **Esito binario «ripreso o compensato» (PRD 1.2).** La revisione 1.3 l'aveva già scartato sulla carta. La misura nomina le celle in cui nessuna delle due strade è percorribile:
  - le 13 celle `bloccato`, dove la direzione del recupero non può procedere finché la causa resta: 6 con il volume assente, 5 con le cartelle non scrivibili, 2 con il volume pieno. Il testo di sostituzione le descrive come situazioni in cui nessuna delle due strade è possibile senza l'utente;
  - `X00-plan-torn`, dove non c'è nulla da riprendere né da compensare, senza alcun esito applicabile in 10 ripetizioni su 10.

  A queste si aggiungono le 17 celle con errore locale, che concludono una direzione solo per i file non colpiti.
- **Classificazione per errno.** È scartata dalla sonda della baseline e la misura lo conferma. Dopo l'espulsione del volume una rinomina restituisce `ENOENT`, lo stesso errno di un file scomparso. Una regola sull'errno non distingue quindi `G-volume-missing`, sistemico e `bloccato` in 30 ripetizioni su 30, da `L-missing`, locale e `parzialmente-recuperato` in 20 su 20. Le prove sono anche altre due: `L-locked` su un passo Cestino non porta alcun errno, solo l'errore Cocoa 513, e quattro classi locali su cinque si riconoscono dal disco prima di agire, senza alcuna chiamata fallita.
- **Fidarsi del log per conoscere lo stato.** È scartata: il log registra intenzioni, e la verità è sul disco. Il Cestino può assegnare all'elemento un altro nome, quindi il percorso registrato non basta a ritrovarlo. Un record può restare troncato a metà, come in `S05-torn` e `X00-plan-torn`. E in ogni punto `-b` il log dice «non fatto» mentre il disco dice «fatto». Decidendo dal disco, la misura non ha alcun `RICONOSCIMENTO_ERRATO` in 146 celle.

<!-- archetipo:wiki section=consequences -->

## Conseguenze

**Vantaggi.**

- La Tappa 3 eredita regole misurate invece di ipotesi: la classificazione per ambito con una tabella di partenza di otto classi, il Cestino cercato per digest, la decisione presa dal disco.
- Da ogni punto diverso da `X00-plan-torn` il recupero conclude nella direzione scelta in 5 ripetizioni su 5, e non riconosce mai male lo stato di un file.
- Un errore sistemico non produce fallimenti in serie: il lotto si ferma al primo passo che lo incontra.
- «Bloccato» è riservato a 13 casi nominati, tutti sistemici. Un errore locale non ferma mai il lotto.

**Svantaggi.**

- «Compensato» promette meno di un ritorno allo stato di partenza: 57 celle su 59 lasciano scostamenti, che l'interfaccia deve dichiarare.
- Il Cestino trattiene le copie annullate. Il prodotto non può ritrovare una voce modificata o sparita dal Cestino, né dire perché manca.
- Il salto per file separa la coppia immagine-sidecar in 8 celle con errore locale. Il salto per file (FR-079) entra in tensione con la coppia che viaggia unita (FR-053), e la Tappa 3 deve decidere se un errore locale sull'immagine debba fermare anche il suo sidecar. Questo cancello misura solo che la separazione, se c'è, viene riferita.
- L'esito in più entra nell'interfaccia, nella cronologia dei lotti (FR-078) e nel resoconto (FR-084).

**Implicazioni operative per la Tappa 3.**

- **Ogni passo va progettato idempotente e osservabile dal disco.** Il recupero deve poter stabilire se un passo è fatto guardando il disco, per digest, senza fidarsi del log.
- **Il registro deve tollerare un record troncato.** Lo riconosce, ne conserva il frammento come evidenza e torna all'ultima riga completa. Il registro del prodotto dovrebbe inoltre annotare ciò che il recupero ha riconosciuto: quello del banco non riconcilia il log, e un secondo recupero riferisce di nuovo la stessa divergenza (`D01/resume`).
- **Gli esiti fanno parte dell'interfaccia**, non del registro interno. «Bloccato in attesa dell'utente» va mostrato con la ragione e con le due vie, riprovare e abbandonare. Un arresto durante la scrittura del piano va riconosciuto e dichiarato come «interrotto prima di agire», non come «bloccato» né come errore.
- **Gli scostamenti di una compensazione vanno dichiarati all'utente** dopo un annullamento (FR-083): l'`mtime` delle cartelle toccate, le copie annullate nel Cestino, `.DS_Store` creato dal sistema e, in un annullamento parziale, ogni file non riportato con percorso e motivo.
- **La direzione di una compensazione avviata va ereditata con un proprio test**, perché questa matrice non la misura.
- **Lo spazio esaurito va trattato su ogni passo**, rinomine comprese (`X03-prepare/resume/G-space-exhausted`).
- **I temporanei di copia** sono rimossi dal banco con `unlink`, come artefatti del lotto. Il prodotto deve dichiarare la stessa politica, o un'altra, rispetto a NFR-A1.
- **Il banco è la base dei test di iniezione di arresti**, ma non gira in integrazione continua: portarlo in CI spetta alla Tappa 3. Prima va corretto il riempimento del volume di `G-space-exhausted`, che non è affidabile.

**Limiti di attribuzione.**

- **`SIGKILL` non equivale a una perdita di alimentazione.** Simula la caduta del processo, e ciò che è nella cache delle pagine sopravvive. Perdita di alimentazione e kernel panic non sono coperti dalla misura.
- **È stato provato un solo tipo di volume**, un volume APFS locale su immagine disco. Volume esterno, cartella sincronizzata e volume di rete spettano al cancello n°2: nessun esito di questa pagina vale per loro.
- **Il contratto di durabilità di `DurableState` (ADR-003) non è provato da questo cancello.** Il registro di intenti era un file JSONL sul volume ospite, una riga per record scritta con una sola `write(2)` e seguita da `F_FULLFSYNC`.
- **Il lotto di prova è unico**, con 5 operazioni e 10 passi e il sidecar `<radice>.xmp`. Il doppio arresto è coperto solo da `D01` e `D02`, e le perturbazioni da tre punti. L'interruzione prima di agire di FR-080 e il motivo `stato-non-riconoscibile` sono prodotti dai test del banco, non dalla matrice.

<!-- archetipo:wiki section=verification -->

## Verifica

- `Spikes/04-crash-recovery/RESULT.md` contiene la configurazione, i limiti dichiarati, una riga per ciascuno dei 61 punti, le 74 compensazioni con i loro scostamenti, le otto classi di errore, i 13 punti bloccati, le 53 separazioni, i 2 esiti non supportabili, l'esito su ADR-007 con il testo di sostituzione e le conseguenze per la costruzione.
- `Spikes/04-crash-recovery/measurements/crash-matrix-20261116T154019Z-0eefc599.json` è la misura versionata: profilo `full`, 146 celle, 5 ripetizioni, impronta dell'host e digest del manifest delle fixture. È stata eseguita in 21 parti, unite da `crashbench combine-matrix` con `COPERTURA completa 146/146`.
- I sottocomandi che producono l'evidenza si eseguono con il binario `.build/debug/crashbench`, secondo `Spikes/04-crash-recovery/PROCEDURE.md`:
  - `crashbench run-matrix --profile full --repetitions 5` esegue la matrice in processi figli e verifica che ogni figlio muoia per segnale 9 nel punto chiesto;
  - `crashbench run --crash-at <punto>` esegue il lotto e lo arresta con `SIGKILL` nel punto scelto;
  - `crashbench recover --strategy resume|compensate` recupera in un nuovo processo e stampa lo stato dei passi, le posizioni delle coppie, le separazioni, le divergenze fra log e disco e la riga `ESITO`.
- `Spikes/04-crash-recovery/Sources/CrashKit/OutcomeClassifier.swift` è il classificatore degli esiti usato per la misura: una funzione pura con otto regole in ordine, in cui `bloccato` nasce solo dalla regola 4. Conosce i cinque esiti del PRD più `NON_SUPPORTABILE`. Il sesto esito è l'emendamento che la misura propone, e il banco non lo implementa.
- `Spikes/04-crash-recovery/Sources/CrashKit/ErrorClassifier.swift` è il classificatore per ambito. Verifica il volume (UUID della radice del lotto contro quello del piano), la scrittura (`access(W_OK)`), lo spazio (`ENOSPC`, `EDQUOT`) e poi le cause locali dal disco. Un fallimento che non corrisponde a nessuna classe resta `nonClassificato`.
- La suite `RecoveryScenarioTests` (`swift test --package-path Spikes/04-crash-recovery`, con un timeout di almeno 600 s) raggiunge ognuno dei cinque esiti e i due motivi di `NON_SUPPORTABILE` su un volume reale. Li asserisce sull'istantanea del disco, non sulla riga stampata.
- La suite `ResultTraceabilityTests` verifica che ogni riga di `RESULT.md` trovi la propria cella nel JSON versionato, e viceversa. Controlla anche la simmetria di AC-7: nessuna cella `NON_SUPPORTABILE` compare fra i punti bloccati. Un caso di controllo altera il documento in memoria e pretende che il confronto lo rilevi.

Il codice di prodotto che adotterà questa semantica, la macchina a stati `FileOps` della Tappa 3, non esiste ancora. Quando esisterà, la verifica di adozione passerà dai suoi test di iniezione di arresti.

## Concetti collegati

- [Mappa dei contesti](/architecture/context-map.md) — le aree *Operazioni su file* e *Stato durevole*
- [Sviluppo e operatività](/operations/development.md) — l'esito dei cancelli tecnici e la toolchain del banco
- [PRD di iMAGE Surfer](/references/prd.md) — ADR-003, ADR-007, ADR-015, FR-053, FR-078…FR-084, NFR-A1
