# Spec: editor/table-editing

## Purpose

Provide practical table editing in collaborative Campsite notes while preserving the existing table document and rendering contracts.

## ADDED Requirements

### Requirement: Insert and remove rows and columns

An editor with note edit access SHALL be able to insert a row or column before or after the active table position, and SHALL retain the existing commands for deleting the active row or column and the whole table. Controls SHALL be disabled when the corresponding command is unavailable.

Verification: Test

#### Scenario: Insert around the active row

- **WHEN** an editor places the cursor in a table row and chooses insert row before or after
- **THEN** a new row is created at the requested position and the transaction is synchronized to collaborators

#### Scenario: Unsupported structural action

- **WHEN** the active selection cannot support a table command
- **THEN** the corresponding control is disabled and no document change occurs

### Requirement: Merge and split cells

An editor SHALL be able to merge a valid selected cell rectangle and split a merged cell when the installed table extension permits the operation. The UI SHALL expose truthful availability and SHALL not silently alter unrelated cells.

Verification: Test

#### Scenario: Merge selected cells

- **WHEN** an editor selects a valid rectangular group of cells and chooses merge
- **THEN** the cells become one merged cell with the table content and structure represented by the existing table schema

#### Scenario: Split a merged cell

- **WHEN** the cursor is in a merged cell and the editor chooses split
- **THEN** the merged cell is divided according to the table command semantics and the result remains valid table content

### Requirement: Header row and column controls

An editor SHALL be able to toggle the active table's header row and header column using the existing header node/command semantics. The resulting document SHALL render header cells as semantic table headers.

Verification: Test

#### Scenario: Toggle a header row

- **WHEN** an editor toggles the header-row control
- **THEN** the first row changes between header and regular-cell semantics and serialized HTML uses `th` for header cells

### Requirement: Cell presentation

An editor SHALL be able to set supported cell text alignment and choose from the approved background-color tokens. Presentation controls SHALL remain usable in light and dark themes and SHALL expose accessible names.

Verification: Demonstration

#### Scenario: Format a cell

- **WHEN** an editor selects a cell and chooses alignment or a background token
- **THEN** the cell presentation changes, persists through reload, and remains visible to collaborators

### Requirement: Paste TSV and CSV into tables

When the active selection is inside a table, the editor SHALL recognize rectangular TSV and supported CSV clipboard text and populate cells from the active cell without modifying content outside that table. Quoted CSV fields SHALL preserve commas and escaped quotes. Input that is malformed, empty, or outside a table SHALL follow the existing paste behavior.

Verification: Test

#### Scenario: Paste TSV

- **WHEN** an editor pastes tab-separated rows into a table cell
- **THEN** values populate successive cells and rows from the active cell, bounded by the existing table dimensions

#### Scenario: Paste quoted CSV

- **WHEN** an editor pastes CSV containing a quoted field with a comma and escaped quotes
- **THEN** the field is inserted as one cell with its intended text

#### Scenario: Paste outside a table

- **WHEN** an editor pastes the same clipboard text into a paragraph
- **THEN** normal existing paste behavior is preserved

### Requirement: Collaborative and format compatibility

Table edits SHALL use the existing editor collaboration transactions, SHALL converge for concurrent clients according to the current Yjs integration, and SHALL remain readable by the existing table JSON/HTML consumers. This change SHALL NOT require a schema-version bump unless a separately reviewed compatibility gap is demonstrated.

Verification: Test

#### Scenario: Collaborator observes and reloads an edit

- **WHEN** one collaborator changes table structure or pastes tabular data
- **THEN** a second collaborator observes the same valid table and the change remains after reload
