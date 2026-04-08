// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'database.dart';

// ignore_for_file: type=lint
class $ProductsTable extends Products with TableInfo<$ProductsTable, Product> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ProductsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
      'id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _artikelnummerMeta =
      const VerificationMeta('artikelnummer');
  @override
  late final GeneratedColumn<String> artikelnummer = GeneratedColumn<String>(
      'artikelnummer', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: true,
      defaultConstraints: GeneratedColumn.constraintIsAlways('UNIQUE'));
  static const VerificationMeta _artikelbezeichnungMeta =
      const VerificationMeta('artikelbezeichnung');
  @override
  late final GeneratedColumn<String> artikelbezeichnung =
      GeneratedColumn<String>('artikelbezeichnung', aliasedName, false,
          type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _beschreibungMeta =
      const VerificationMeta('beschreibung');
  @override
  late final GeneratedColumn<String> beschreibung = GeneratedColumn<String>(
      'beschreibung', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _notizenMeta =
      const VerificationMeta('notizen');
  @override
  late final GeneratedColumn<String> notizen = GeneratedColumn<String>(
      'notizen', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _createdAtMeta =
      const VerificationMeta('createdAt');
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
      'created_at', aliasedName, false,
      type: DriftSqlType.dateTime,
      requiredDuringInsert: false,
      defaultValue: currentDateAndTime);
  static const VerificationMeta _updatedAtMeta =
      const VerificationMeta('updatedAt');
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
      'updated_at', aliasedName, false,
      type: DriftSqlType.dateTime,
      requiredDuringInsert: false,
      defaultValue: currentDateAndTime);
  static const VerificationMeta _deletedAtMeta =
      const VerificationMeta('deletedAt');
  @override
  late final GeneratedColumn<DateTime> deletedAt = GeneratedColumn<DateTime>(
      'deleted_at', aliasedName, true,
      type: DriftSqlType.dateTime, requiredDuringInsert: false);
  @override
  List<GeneratedColumn> get $columns => [
        id,
        artikelnummer,
        artikelbezeichnung,
        beschreibung,
        notizen,
        createdAt,
        updatedAt,
        deletedAt
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'products';
  @override
  VerificationContext validateIntegrity(Insertable<Product> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('artikelnummer')) {
      context.handle(
          _artikelnummerMeta,
          artikelnummer.isAcceptableOrUnknown(
              data['artikelnummer']!, _artikelnummerMeta));
    } else if (isInserting) {
      context.missing(_artikelnummerMeta);
    }
    if (data.containsKey('artikelbezeichnung')) {
      context.handle(
          _artikelbezeichnungMeta,
          artikelbezeichnung.isAcceptableOrUnknown(
              data['artikelbezeichnung']!, _artikelbezeichnungMeta));
    } else if (isInserting) {
      context.missing(_artikelbezeichnungMeta);
    }
    if (data.containsKey('beschreibung')) {
      context.handle(
          _beschreibungMeta,
          beschreibung.isAcceptableOrUnknown(
              data['beschreibung']!, _beschreibungMeta));
    }
    if (data.containsKey('notizen')) {
      context.handle(_notizenMeta,
          notizen.isAcceptableOrUnknown(data['notizen']!, _notizenMeta));
    }
    if (data.containsKey('created_at')) {
      context.handle(_createdAtMeta,
          createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta));
    }
    if (data.containsKey('updated_at')) {
      context.handle(_updatedAtMeta,
          updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta));
    }
    if (data.containsKey('deleted_at')) {
      context.handle(_deletedAtMeta,
          deletedAt.isAcceptableOrUnknown(data['deleted_at']!, _deletedAtMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Product map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Product(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}id'])!,
      artikelnummer: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}artikelnummer'])!,
      artikelbezeichnung: attachedDatabase.typeMapping.read(
          DriftSqlType.string, data['${effectivePrefix}artikelbezeichnung'])!,
      beschreibung: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}beschreibung']),
      notizen: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}notizen']),
      createdAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}created_at'])!,
      updatedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}updated_at'])!,
      deletedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}deleted_at']),
    );
  }

  @override
  $ProductsTable createAlias(String alias) {
    return $ProductsTable(attachedDatabase, alias);
  }
}

class Product extends DataClass implements Insertable<Product> {
  /// UUID — wird in der App per `uuid`-Package erzeugt, nicht von SQLite.
  /// Grund: Supabase-Sync-Kompatibilität (keine Auto-Increment-Kollisionen).
  final String id;

  /// Artikelnummer wie im Betrieb verwendet (z.B. "LK-001"). Unique.
  final String artikelnummer;

  /// Menschenlesbare Bezeichnung ("Leberkäse grob").
  final String artikelbezeichnung;
  final String? beschreibung;
  final String? notizen;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;
  const Product(
      {required this.id,
      required this.artikelnummer,
      required this.artikelbezeichnung,
      this.beschreibung,
      this.notizen,
      required this.createdAt,
      required this.updatedAt,
      this.deletedAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['artikelnummer'] = Variable<String>(artikelnummer);
    map['artikelbezeichnung'] = Variable<String>(artikelbezeichnung);
    if (!nullToAbsent || beschreibung != null) {
      map['beschreibung'] = Variable<String>(beschreibung);
    }
    if (!nullToAbsent || notizen != null) {
      map['notizen'] = Variable<String>(notizen);
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    if (!nullToAbsent || deletedAt != null) {
      map['deleted_at'] = Variable<DateTime>(deletedAt);
    }
    return map;
  }

  ProductsCompanion toCompanion(bool nullToAbsent) {
    return ProductsCompanion(
      id: Value(id),
      artikelnummer: Value(artikelnummer),
      artikelbezeichnung: Value(artikelbezeichnung),
      beschreibung: beschreibung == null && nullToAbsent
          ? const Value.absent()
          : Value(beschreibung),
      notizen: notizen == null && nullToAbsent
          ? const Value.absent()
          : Value(notizen),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
      deletedAt: deletedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(deletedAt),
    );
  }

  factory Product.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Product(
      id: serializer.fromJson<String>(json['id']),
      artikelnummer: serializer.fromJson<String>(json['artikelnummer']),
      artikelbezeichnung:
          serializer.fromJson<String>(json['artikelbezeichnung']),
      beschreibung: serializer.fromJson<String?>(json['beschreibung']),
      notizen: serializer.fromJson<String?>(json['notizen']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
      deletedAt: serializer.fromJson<DateTime?>(json['deletedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'artikelnummer': serializer.toJson<String>(artikelnummer),
      'artikelbezeichnung': serializer.toJson<String>(artikelbezeichnung),
      'beschreibung': serializer.toJson<String?>(beschreibung),
      'notizen': serializer.toJson<String?>(notizen),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
      'deletedAt': serializer.toJson<DateTime?>(deletedAt),
    };
  }

  Product copyWith(
          {String? id,
          String? artikelnummer,
          String? artikelbezeichnung,
          Value<String?> beschreibung = const Value.absent(),
          Value<String?> notizen = const Value.absent(),
          DateTime? createdAt,
          DateTime? updatedAt,
          Value<DateTime?> deletedAt = const Value.absent()}) =>
      Product(
        id: id ?? this.id,
        artikelnummer: artikelnummer ?? this.artikelnummer,
        artikelbezeichnung: artikelbezeichnung ?? this.artikelbezeichnung,
        beschreibung:
            beschreibung.present ? beschreibung.value : this.beschreibung,
        notizen: notizen.present ? notizen.value : this.notizen,
        createdAt: createdAt ?? this.createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
        deletedAt: deletedAt.present ? deletedAt.value : this.deletedAt,
      );
  Product copyWithCompanion(ProductsCompanion data) {
    return Product(
      id: data.id.present ? data.id.value : this.id,
      artikelnummer: data.artikelnummer.present
          ? data.artikelnummer.value
          : this.artikelnummer,
      artikelbezeichnung: data.artikelbezeichnung.present
          ? data.artikelbezeichnung.value
          : this.artikelbezeichnung,
      beschreibung: data.beschreibung.present
          ? data.beschreibung.value
          : this.beschreibung,
      notizen: data.notizen.present ? data.notizen.value : this.notizen,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      deletedAt: data.deletedAt.present ? data.deletedAt.value : this.deletedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Product(')
          ..write('id: $id, ')
          ..write('artikelnummer: $artikelnummer, ')
          ..write('artikelbezeichnung: $artikelbezeichnung, ')
          ..write('beschreibung: $beschreibung, ')
          ..write('notizen: $notizen, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, artikelnummer, artikelbezeichnung,
      beschreibung, notizen, createdAt, updatedAt, deletedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Product &&
          other.id == this.id &&
          other.artikelnummer == this.artikelnummer &&
          other.artikelbezeichnung == this.artikelbezeichnung &&
          other.beschreibung == this.beschreibung &&
          other.notizen == this.notizen &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt &&
          other.deletedAt == this.deletedAt);
}

class ProductsCompanion extends UpdateCompanion<Product> {
  final Value<String> id;
  final Value<String> artikelnummer;
  final Value<String> artikelbezeichnung;
  final Value<String?> beschreibung;
  final Value<String?> notizen;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<DateTime?> deletedAt;
  final Value<int> rowid;
  const ProductsCompanion({
    this.id = const Value.absent(),
    this.artikelnummer = const Value.absent(),
    this.artikelbezeichnung = const Value.absent(),
    this.beschreibung = const Value.absent(),
    this.notizen = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ProductsCompanion.insert({
    required String id,
    required String artikelnummer,
    required String artikelbezeichnung,
    this.beschreibung = const Value.absent(),
    this.notizen = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  })  : id = Value(id),
        artikelnummer = Value(artikelnummer),
        artikelbezeichnung = Value(artikelbezeichnung);
  static Insertable<Product> custom({
    Expression<String>? id,
    Expression<String>? artikelnummer,
    Expression<String>? artikelbezeichnung,
    Expression<String>? beschreibung,
    Expression<String>? notizen,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<DateTime>? deletedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (artikelnummer != null) 'artikelnummer': artikelnummer,
      if (artikelbezeichnung != null) 'artikelbezeichnung': artikelbezeichnung,
      if (beschreibung != null) 'beschreibung': beschreibung,
      if (notizen != null) 'notizen': notizen,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (deletedAt != null) 'deleted_at': deletedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ProductsCompanion copyWith(
      {Value<String>? id,
      Value<String>? artikelnummer,
      Value<String>? artikelbezeichnung,
      Value<String?>? beschreibung,
      Value<String?>? notizen,
      Value<DateTime>? createdAt,
      Value<DateTime>? updatedAt,
      Value<DateTime?>? deletedAt,
      Value<int>? rowid}) {
    return ProductsCompanion(
      id: id ?? this.id,
      artikelnummer: artikelnummer ?? this.artikelnummer,
      artikelbezeichnung: artikelbezeichnung ?? this.artikelbezeichnung,
      beschreibung: beschreibung ?? this.beschreibung,
      notizen: notizen ?? this.notizen,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: deletedAt ?? this.deletedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (artikelnummer.present) {
      map['artikelnummer'] = Variable<String>(artikelnummer.value);
    }
    if (artikelbezeichnung.present) {
      map['artikelbezeichnung'] = Variable<String>(artikelbezeichnung.value);
    }
    if (beschreibung.present) {
      map['beschreibung'] = Variable<String>(beschreibung.value);
    }
    if (notizen.present) {
      map['notizen'] = Variable<String>(notizen.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (deletedAt.present) {
      map['deleted_at'] = Variable<DateTime>(deletedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ProductsCompanion(')
          ..write('id: $id, ')
          ..write('artikelnummer: $artikelnummer, ')
          ..write('artikelbezeichnung: $artikelbezeichnung, ')
          ..write('beschreibung: $beschreibung, ')
          ..write('notizen: $notizen, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ProductStepsTable extends ProductSteps
    with TableInfo<$ProductStepsTable, ProductStep> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ProductStepsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
      'id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _productIdMeta =
      const VerificationMeta('productId');
  @override
  late final GeneratedColumn<String> productId = GeneratedColumn<String>(
      'product_id', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: true,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('REFERENCES products (id)'));
  static const VerificationMeta _reihenfolgeMeta =
      const VerificationMeta('reihenfolge');
  @override
  late final GeneratedColumn<int> reihenfolge = GeneratedColumn<int>(
      'reihenfolge', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _abteilungMeta =
      const VerificationMeta('abteilung');
  @override
  late final GeneratedColumn<String> abteilung = GeneratedColumn<String>(
      'abteilung', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _basisMengeKgMeta =
      const VerificationMeta('basisMengeKg');
  @override
  late final GeneratedColumn<double> basisMengeKg = GeneratedColumn<double>(
      'basis_menge_kg', aliasedName, false,
      type: DriftSqlType.double, requiredDuringInsert: true);
  static const VerificationMeta _basisDauerMinutenMeta =
      const VerificationMeta('basisDauerMinuten');
  @override
  late final GeneratedColumn<double> basisDauerMinuten =
      GeneratedColumn<double>('basis_dauer_minuten', aliasedName, false,
          type: DriftSqlType.double, requiredDuringInsert: true);
  static const VerificationMeta _fixZeitMinutenMeta =
      const VerificationMeta('fixZeitMinuten');
  @override
  late final GeneratedColumn<double> fixZeitMinuten = GeneratedColumn<double>(
      'fix_zeit_minuten', aliasedName, true,
      type: DriftSqlType.double, requiredDuringInsert: false);
  static const VerificationMeta _dauerStdAbweichungMeta =
      const VerificationMeta('dauerStdAbweichung');
  @override
  late final GeneratedColumn<double> dauerStdAbweichung =
      GeneratedColumn<double>('dauer_std_abweichung', aliasedName, true,
          type: DriftSqlType.double, requiredDuringInsert: false);
  static const VerificationMeta _basisMitarbeiterMeta =
      const VerificationMeta('basisMitarbeiter');
  @override
  late final GeneratedColumn<int> basisMitarbeiter = GeneratedColumn<int>(
      'basis_mitarbeiter', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _basisAnzahlMessungenMeta =
      const VerificationMeta('basisAnzahlMessungen');
  @override
  late final GeneratedColumn<int> basisAnzahlMessungen = GeneratedColumn<int>(
      'basis_anzahl_messungen', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(0));
  static const VerificationMeta _maschinenEinstellungenJsonMeta =
      const VerificationMeta('maschinenEinstellungenJson');
  @override
  late final GeneratedColumn<String> maschinenEinstellungenJson =
      GeneratedColumn<String>('maschinen_einstellungen_json', aliasedName, true,
          type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _notizenMeta =
      const VerificationMeta('notizen');
  @override
  late final GeneratedColumn<String> notizen = GeneratedColumn<String>(
      'notizen', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _createdAtMeta =
      const VerificationMeta('createdAt');
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
      'created_at', aliasedName, false,
      type: DriftSqlType.dateTime,
      requiredDuringInsert: false,
      defaultValue: currentDateAndTime);
  static const VerificationMeta _updatedAtMeta =
      const VerificationMeta('updatedAt');
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
      'updated_at', aliasedName, false,
      type: DriftSqlType.dateTime,
      requiredDuringInsert: false,
      defaultValue: currentDateAndTime);
  static const VerificationMeta _deletedAtMeta =
      const VerificationMeta('deletedAt');
  @override
  late final GeneratedColumn<DateTime> deletedAt = GeneratedColumn<DateTime>(
      'deleted_at', aliasedName, true,
      type: DriftSqlType.dateTime, requiredDuringInsert: false);
  @override
  List<GeneratedColumn> get $columns => [
        id,
        productId,
        reihenfolge,
        abteilung,
        basisMengeKg,
        basisDauerMinuten,
        fixZeitMinuten,
        dauerStdAbweichung,
        basisMitarbeiter,
        basisAnzahlMessungen,
        maschinenEinstellungenJson,
        notizen,
        createdAt,
        updatedAt,
        deletedAt
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'product_steps';
  @override
  VerificationContext validateIntegrity(Insertable<ProductStep> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('product_id')) {
      context.handle(_productIdMeta,
          productId.isAcceptableOrUnknown(data['product_id']!, _productIdMeta));
    } else if (isInserting) {
      context.missing(_productIdMeta);
    }
    if (data.containsKey('reihenfolge')) {
      context.handle(
          _reihenfolgeMeta,
          reihenfolge.isAcceptableOrUnknown(
              data['reihenfolge']!, _reihenfolgeMeta));
    } else if (isInserting) {
      context.missing(_reihenfolgeMeta);
    }
    if (data.containsKey('abteilung')) {
      context.handle(_abteilungMeta,
          abteilung.isAcceptableOrUnknown(data['abteilung']!, _abteilungMeta));
    } else if (isInserting) {
      context.missing(_abteilungMeta);
    }
    if (data.containsKey('basis_menge_kg')) {
      context.handle(
          _basisMengeKgMeta,
          basisMengeKg.isAcceptableOrUnknown(
              data['basis_menge_kg']!, _basisMengeKgMeta));
    } else if (isInserting) {
      context.missing(_basisMengeKgMeta);
    }
    if (data.containsKey('basis_dauer_minuten')) {
      context.handle(
          _basisDauerMinutenMeta,
          basisDauerMinuten.isAcceptableOrUnknown(
              data['basis_dauer_minuten']!, _basisDauerMinutenMeta));
    } else if (isInserting) {
      context.missing(_basisDauerMinutenMeta);
    }
    if (data.containsKey('fix_zeit_minuten')) {
      context.handle(
          _fixZeitMinutenMeta,
          fixZeitMinuten.isAcceptableOrUnknown(
              data['fix_zeit_minuten']!, _fixZeitMinutenMeta));
    }
    if (data.containsKey('dauer_std_abweichung')) {
      context.handle(
          _dauerStdAbweichungMeta,
          dauerStdAbweichung.isAcceptableOrUnknown(
              data['dauer_std_abweichung']!, _dauerStdAbweichungMeta));
    }
    if (data.containsKey('basis_mitarbeiter')) {
      context.handle(
          _basisMitarbeiterMeta,
          basisMitarbeiter.isAcceptableOrUnknown(
              data['basis_mitarbeiter']!, _basisMitarbeiterMeta));
    } else if (isInserting) {
      context.missing(_basisMitarbeiterMeta);
    }
    if (data.containsKey('basis_anzahl_messungen')) {
      context.handle(
          _basisAnzahlMessungenMeta,
          basisAnzahlMessungen.isAcceptableOrUnknown(
              data['basis_anzahl_messungen']!, _basisAnzahlMessungenMeta));
    }
    if (data.containsKey('maschinen_einstellungen_json')) {
      context.handle(
          _maschinenEinstellungenJsonMeta,
          maschinenEinstellungenJson.isAcceptableOrUnknown(
              data['maschinen_einstellungen_json']!,
              _maschinenEinstellungenJsonMeta));
    }
    if (data.containsKey('notizen')) {
      context.handle(_notizenMeta,
          notizen.isAcceptableOrUnknown(data['notizen']!, _notizenMeta));
    }
    if (data.containsKey('created_at')) {
      context.handle(_createdAtMeta,
          createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta));
    }
    if (data.containsKey('updated_at')) {
      context.handle(_updatedAtMeta,
          updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta));
    }
    if (data.containsKey('deleted_at')) {
      context.handle(_deletedAtMeta,
          deletedAt.isAcceptableOrUnknown(data['deleted_at']!, _deletedAtMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  ProductStep map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ProductStep(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}id'])!,
      productId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}product_id'])!,
      reihenfolge: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}reihenfolge'])!,
      abteilung: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}abteilung'])!,
      basisMengeKg: attachedDatabase.typeMapping
          .read(DriftSqlType.double, data['${effectivePrefix}basis_menge_kg'])!,
      basisDauerMinuten: attachedDatabase.typeMapping.read(
          DriftSqlType.double, data['${effectivePrefix}basis_dauer_minuten'])!,
      fixZeitMinuten: attachedDatabase.typeMapping.read(
          DriftSqlType.double, data['${effectivePrefix}fix_zeit_minuten']),
      dauerStdAbweichung: attachedDatabase.typeMapping.read(
          DriftSqlType.double, data['${effectivePrefix}dauer_std_abweichung']),
      basisMitarbeiter: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}basis_mitarbeiter'])!,
      basisAnzahlMessungen: attachedDatabase.typeMapping.read(
          DriftSqlType.int, data['${effectivePrefix}basis_anzahl_messungen'])!,
      maschinenEinstellungenJson: attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}maschinen_einstellungen_json']),
      notizen: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}notizen']),
      createdAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}created_at'])!,
      updatedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}updated_at'])!,
      deletedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}deleted_at']),
    );
  }

  @override
  $ProductStepsTable createAlias(String alias) {
    return $ProductStepsTable(attachedDatabase, alias);
  }
}

class ProductStep extends DataClass implements Insertable<ProductStep> {
  final String id;
  final String productId;

  /// Position in der Abfolge (1, 2, 3, ...). Erlaubt Umsortieren per Drag&Drop.
  final int reihenfolge;

  /// Abteilung, die diesen Schritt ausführt — gespeichert als [Abteilung.dbValue].
  final String abteilung;

  /// Referenzmenge in kg, auf die sich [basisDauerMinuten] bezieht.
  final double basisMengeKg;

  /// Basis-Dauer in Minuten für [basisMengeKg].
  final double basisDauerMinuten;

  /// Fixe Rüstzeit, unabhängig von der Menge. NULL/0 = rein lineare Skalierung.
  final double? fixZeitMinuten;

  /// Standardabweichung der gemessenen Dauern (aus [ProductionRuns] berechnet).
  /// UI kann damit "90 min ± 12 min" ehrlich anzeigen.
  final double? dauerStdAbweichung;
  final int basisMitarbeiter;

  /// Anzahl der Runs, aus denen die Basis-Werte berechnet wurden.
  /// 0 = noch nie gemessen (Schätzwerte). Ab ~5 zunehmend verlässlich.
  final int basisAnzahlMessungen;

  /// JSON-Objekt mit Maschineneinstellungen (z.B. {"temperatur": 72, "zeit_min": 45}).
  /// Bewusst frei, weil jede Abteilung andere Parameter hat. Strukturierte
  /// Validierung passiert in der Domain-Schicht.
  final String? maschinenEinstellungenJson;
  final String? notizen;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;
  const ProductStep(
      {required this.id,
      required this.productId,
      required this.reihenfolge,
      required this.abteilung,
      required this.basisMengeKg,
      required this.basisDauerMinuten,
      this.fixZeitMinuten,
      this.dauerStdAbweichung,
      required this.basisMitarbeiter,
      required this.basisAnzahlMessungen,
      this.maschinenEinstellungenJson,
      this.notizen,
      required this.createdAt,
      required this.updatedAt,
      this.deletedAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['product_id'] = Variable<String>(productId);
    map['reihenfolge'] = Variable<int>(reihenfolge);
    map['abteilung'] = Variable<String>(abteilung);
    map['basis_menge_kg'] = Variable<double>(basisMengeKg);
    map['basis_dauer_minuten'] = Variable<double>(basisDauerMinuten);
    if (!nullToAbsent || fixZeitMinuten != null) {
      map['fix_zeit_minuten'] = Variable<double>(fixZeitMinuten);
    }
    if (!nullToAbsent || dauerStdAbweichung != null) {
      map['dauer_std_abweichung'] = Variable<double>(dauerStdAbweichung);
    }
    map['basis_mitarbeiter'] = Variable<int>(basisMitarbeiter);
    map['basis_anzahl_messungen'] = Variable<int>(basisAnzahlMessungen);
    if (!nullToAbsent || maschinenEinstellungenJson != null) {
      map['maschinen_einstellungen_json'] =
          Variable<String>(maschinenEinstellungenJson);
    }
    if (!nullToAbsent || notizen != null) {
      map['notizen'] = Variable<String>(notizen);
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    if (!nullToAbsent || deletedAt != null) {
      map['deleted_at'] = Variable<DateTime>(deletedAt);
    }
    return map;
  }

  ProductStepsCompanion toCompanion(bool nullToAbsent) {
    return ProductStepsCompanion(
      id: Value(id),
      productId: Value(productId),
      reihenfolge: Value(reihenfolge),
      abteilung: Value(abteilung),
      basisMengeKg: Value(basisMengeKg),
      basisDauerMinuten: Value(basisDauerMinuten),
      fixZeitMinuten: fixZeitMinuten == null && nullToAbsent
          ? const Value.absent()
          : Value(fixZeitMinuten),
      dauerStdAbweichung: dauerStdAbweichung == null && nullToAbsent
          ? const Value.absent()
          : Value(dauerStdAbweichung),
      basisMitarbeiter: Value(basisMitarbeiter),
      basisAnzahlMessungen: Value(basisAnzahlMessungen),
      maschinenEinstellungenJson:
          maschinenEinstellungenJson == null && nullToAbsent
              ? const Value.absent()
              : Value(maschinenEinstellungenJson),
      notizen: notizen == null && nullToAbsent
          ? const Value.absent()
          : Value(notizen),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
      deletedAt: deletedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(deletedAt),
    );
  }

  factory ProductStep.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ProductStep(
      id: serializer.fromJson<String>(json['id']),
      productId: serializer.fromJson<String>(json['productId']),
      reihenfolge: serializer.fromJson<int>(json['reihenfolge']),
      abteilung: serializer.fromJson<String>(json['abteilung']),
      basisMengeKg: serializer.fromJson<double>(json['basisMengeKg']),
      basisDauerMinuten: serializer.fromJson<double>(json['basisDauerMinuten']),
      fixZeitMinuten: serializer.fromJson<double?>(json['fixZeitMinuten']),
      dauerStdAbweichung:
          serializer.fromJson<double?>(json['dauerStdAbweichung']),
      basisMitarbeiter: serializer.fromJson<int>(json['basisMitarbeiter']),
      basisAnzahlMessungen:
          serializer.fromJson<int>(json['basisAnzahlMessungen']),
      maschinenEinstellungenJson:
          serializer.fromJson<String?>(json['maschinenEinstellungenJson']),
      notizen: serializer.fromJson<String?>(json['notizen']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
      deletedAt: serializer.fromJson<DateTime?>(json['deletedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'productId': serializer.toJson<String>(productId),
      'reihenfolge': serializer.toJson<int>(reihenfolge),
      'abteilung': serializer.toJson<String>(abteilung),
      'basisMengeKg': serializer.toJson<double>(basisMengeKg),
      'basisDauerMinuten': serializer.toJson<double>(basisDauerMinuten),
      'fixZeitMinuten': serializer.toJson<double?>(fixZeitMinuten),
      'dauerStdAbweichung': serializer.toJson<double?>(dauerStdAbweichung),
      'basisMitarbeiter': serializer.toJson<int>(basisMitarbeiter),
      'basisAnzahlMessungen': serializer.toJson<int>(basisAnzahlMessungen),
      'maschinenEinstellungenJson':
          serializer.toJson<String?>(maschinenEinstellungenJson),
      'notizen': serializer.toJson<String?>(notizen),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
      'deletedAt': serializer.toJson<DateTime?>(deletedAt),
    };
  }

  ProductStep copyWith(
          {String? id,
          String? productId,
          int? reihenfolge,
          String? abteilung,
          double? basisMengeKg,
          double? basisDauerMinuten,
          Value<double?> fixZeitMinuten = const Value.absent(),
          Value<double?> dauerStdAbweichung = const Value.absent(),
          int? basisMitarbeiter,
          int? basisAnzahlMessungen,
          Value<String?> maschinenEinstellungenJson = const Value.absent(),
          Value<String?> notizen = const Value.absent(),
          DateTime? createdAt,
          DateTime? updatedAt,
          Value<DateTime?> deletedAt = const Value.absent()}) =>
      ProductStep(
        id: id ?? this.id,
        productId: productId ?? this.productId,
        reihenfolge: reihenfolge ?? this.reihenfolge,
        abteilung: abteilung ?? this.abteilung,
        basisMengeKg: basisMengeKg ?? this.basisMengeKg,
        basisDauerMinuten: basisDauerMinuten ?? this.basisDauerMinuten,
        fixZeitMinuten:
            fixZeitMinuten.present ? fixZeitMinuten.value : this.fixZeitMinuten,
        dauerStdAbweichung: dauerStdAbweichung.present
            ? dauerStdAbweichung.value
            : this.dauerStdAbweichung,
        basisMitarbeiter: basisMitarbeiter ?? this.basisMitarbeiter,
        basisAnzahlMessungen: basisAnzahlMessungen ?? this.basisAnzahlMessungen,
        maschinenEinstellungenJson: maschinenEinstellungenJson.present
            ? maschinenEinstellungenJson.value
            : this.maschinenEinstellungenJson,
        notizen: notizen.present ? notizen.value : this.notizen,
        createdAt: createdAt ?? this.createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
        deletedAt: deletedAt.present ? deletedAt.value : this.deletedAt,
      );
  ProductStep copyWithCompanion(ProductStepsCompanion data) {
    return ProductStep(
      id: data.id.present ? data.id.value : this.id,
      productId: data.productId.present ? data.productId.value : this.productId,
      reihenfolge:
          data.reihenfolge.present ? data.reihenfolge.value : this.reihenfolge,
      abteilung: data.abteilung.present ? data.abteilung.value : this.abteilung,
      basisMengeKg: data.basisMengeKg.present
          ? data.basisMengeKg.value
          : this.basisMengeKg,
      basisDauerMinuten: data.basisDauerMinuten.present
          ? data.basisDauerMinuten.value
          : this.basisDauerMinuten,
      fixZeitMinuten: data.fixZeitMinuten.present
          ? data.fixZeitMinuten.value
          : this.fixZeitMinuten,
      dauerStdAbweichung: data.dauerStdAbweichung.present
          ? data.dauerStdAbweichung.value
          : this.dauerStdAbweichung,
      basisMitarbeiter: data.basisMitarbeiter.present
          ? data.basisMitarbeiter.value
          : this.basisMitarbeiter,
      basisAnzahlMessungen: data.basisAnzahlMessungen.present
          ? data.basisAnzahlMessungen.value
          : this.basisAnzahlMessungen,
      maschinenEinstellungenJson: data.maschinenEinstellungenJson.present
          ? data.maschinenEinstellungenJson.value
          : this.maschinenEinstellungenJson,
      notizen: data.notizen.present ? data.notizen.value : this.notizen,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      deletedAt: data.deletedAt.present ? data.deletedAt.value : this.deletedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ProductStep(')
          ..write('id: $id, ')
          ..write('productId: $productId, ')
          ..write('reihenfolge: $reihenfolge, ')
          ..write('abteilung: $abteilung, ')
          ..write('basisMengeKg: $basisMengeKg, ')
          ..write('basisDauerMinuten: $basisDauerMinuten, ')
          ..write('fixZeitMinuten: $fixZeitMinuten, ')
          ..write('dauerStdAbweichung: $dauerStdAbweichung, ')
          ..write('basisMitarbeiter: $basisMitarbeiter, ')
          ..write('basisAnzahlMessungen: $basisAnzahlMessungen, ')
          ..write('maschinenEinstellungenJson: $maschinenEinstellungenJson, ')
          ..write('notizen: $notizen, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
      id,
      productId,
      reihenfolge,
      abteilung,
      basisMengeKg,
      basisDauerMinuten,
      fixZeitMinuten,
      dauerStdAbweichung,
      basisMitarbeiter,
      basisAnzahlMessungen,
      maschinenEinstellungenJson,
      notizen,
      createdAt,
      updatedAt,
      deletedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ProductStep &&
          other.id == this.id &&
          other.productId == this.productId &&
          other.reihenfolge == this.reihenfolge &&
          other.abteilung == this.abteilung &&
          other.basisMengeKg == this.basisMengeKg &&
          other.basisDauerMinuten == this.basisDauerMinuten &&
          other.fixZeitMinuten == this.fixZeitMinuten &&
          other.dauerStdAbweichung == this.dauerStdAbweichung &&
          other.basisMitarbeiter == this.basisMitarbeiter &&
          other.basisAnzahlMessungen == this.basisAnzahlMessungen &&
          other.maschinenEinstellungenJson == this.maschinenEinstellungenJson &&
          other.notizen == this.notizen &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt &&
          other.deletedAt == this.deletedAt);
}

class ProductStepsCompanion extends UpdateCompanion<ProductStep> {
  final Value<String> id;
  final Value<String> productId;
  final Value<int> reihenfolge;
  final Value<String> abteilung;
  final Value<double> basisMengeKg;
  final Value<double> basisDauerMinuten;
  final Value<double?> fixZeitMinuten;
  final Value<double?> dauerStdAbweichung;
  final Value<int> basisMitarbeiter;
  final Value<int> basisAnzahlMessungen;
  final Value<String?> maschinenEinstellungenJson;
  final Value<String?> notizen;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<DateTime?> deletedAt;
  final Value<int> rowid;
  const ProductStepsCompanion({
    this.id = const Value.absent(),
    this.productId = const Value.absent(),
    this.reihenfolge = const Value.absent(),
    this.abteilung = const Value.absent(),
    this.basisMengeKg = const Value.absent(),
    this.basisDauerMinuten = const Value.absent(),
    this.fixZeitMinuten = const Value.absent(),
    this.dauerStdAbweichung = const Value.absent(),
    this.basisMitarbeiter = const Value.absent(),
    this.basisAnzahlMessungen = const Value.absent(),
    this.maschinenEinstellungenJson = const Value.absent(),
    this.notizen = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ProductStepsCompanion.insert({
    required String id,
    required String productId,
    required int reihenfolge,
    required String abteilung,
    required double basisMengeKg,
    required double basisDauerMinuten,
    this.fixZeitMinuten = const Value.absent(),
    this.dauerStdAbweichung = const Value.absent(),
    required int basisMitarbeiter,
    this.basisAnzahlMessungen = const Value.absent(),
    this.maschinenEinstellungenJson = const Value.absent(),
    this.notizen = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  })  : id = Value(id),
        productId = Value(productId),
        reihenfolge = Value(reihenfolge),
        abteilung = Value(abteilung),
        basisMengeKg = Value(basisMengeKg),
        basisDauerMinuten = Value(basisDauerMinuten),
        basisMitarbeiter = Value(basisMitarbeiter);
  static Insertable<ProductStep> custom({
    Expression<String>? id,
    Expression<String>? productId,
    Expression<int>? reihenfolge,
    Expression<String>? abteilung,
    Expression<double>? basisMengeKg,
    Expression<double>? basisDauerMinuten,
    Expression<double>? fixZeitMinuten,
    Expression<double>? dauerStdAbweichung,
    Expression<int>? basisMitarbeiter,
    Expression<int>? basisAnzahlMessungen,
    Expression<String>? maschinenEinstellungenJson,
    Expression<String>? notizen,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<DateTime>? deletedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (productId != null) 'product_id': productId,
      if (reihenfolge != null) 'reihenfolge': reihenfolge,
      if (abteilung != null) 'abteilung': abteilung,
      if (basisMengeKg != null) 'basis_menge_kg': basisMengeKg,
      if (basisDauerMinuten != null) 'basis_dauer_minuten': basisDauerMinuten,
      if (fixZeitMinuten != null) 'fix_zeit_minuten': fixZeitMinuten,
      if (dauerStdAbweichung != null)
        'dauer_std_abweichung': dauerStdAbweichung,
      if (basisMitarbeiter != null) 'basis_mitarbeiter': basisMitarbeiter,
      if (basisAnzahlMessungen != null)
        'basis_anzahl_messungen': basisAnzahlMessungen,
      if (maschinenEinstellungenJson != null)
        'maschinen_einstellungen_json': maschinenEinstellungenJson,
      if (notizen != null) 'notizen': notizen,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (deletedAt != null) 'deleted_at': deletedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ProductStepsCompanion copyWith(
      {Value<String>? id,
      Value<String>? productId,
      Value<int>? reihenfolge,
      Value<String>? abteilung,
      Value<double>? basisMengeKg,
      Value<double>? basisDauerMinuten,
      Value<double?>? fixZeitMinuten,
      Value<double?>? dauerStdAbweichung,
      Value<int>? basisMitarbeiter,
      Value<int>? basisAnzahlMessungen,
      Value<String?>? maschinenEinstellungenJson,
      Value<String?>? notizen,
      Value<DateTime>? createdAt,
      Value<DateTime>? updatedAt,
      Value<DateTime?>? deletedAt,
      Value<int>? rowid}) {
    return ProductStepsCompanion(
      id: id ?? this.id,
      productId: productId ?? this.productId,
      reihenfolge: reihenfolge ?? this.reihenfolge,
      abteilung: abteilung ?? this.abteilung,
      basisMengeKg: basisMengeKg ?? this.basisMengeKg,
      basisDauerMinuten: basisDauerMinuten ?? this.basisDauerMinuten,
      fixZeitMinuten: fixZeitMinuten ?? this.fixZeitMinuten,
      dauerStdAbweichung: dauerStdAbweichung ?? this.dauerStdAbweichung,
      basisMitarbeiter: basisMitarbeiter ?? this.basisMitarbeiter,
      basisAnzahlMessungen: basisAnzahlMessungen ?? this.basisAnzahlMessungen,
      maschinenEinstellungenJson:
          maschinenEinstellungenJson ?? this.maschinenEinstellungenJson,
      notizen: notizen ?? this.notizen,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: deletedAt ?? this.deletedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (productId.present) {
      map['product_id'] = Variable<String>(productId.value);
    }
    if (reihenfolge.present) {
      map['reihenfolge'] = Variable<int>(reihenfolge.value);
    }
    if (abteilung.present) {
      map['abteilung'] = Variable<String>(abteilung.value);
    }
    if (basisMengeKg.present) {
      map['basis_menge_kg'] = Variable<double>(basisMengeKg.value);
    }
    if (basisDauerMinuten.present) {
      map['basis_dauer_minuten'] = Variable<double>(basisDauerMinuten.value);
    }
    if (fixZeitMinuten.present) {
      map['fix_zeit_minuten'] = Variable<double>(fixZeitMinuten.value);
    }
    if (dauerStdAbweichung.present) {
      map['dauer_std_abweichung'] = Variable<double>(dauerStdAbweichung.value);
    }
    if (basisMitarbeiter.present) {
      map['basis_mitarbeiter'] = Variable<int>(basisMitarbeiter.value);
    }
    if (basisAnzahlMessungen.present) {
      map['basis_anzahl_messungen'] = Variable<int>(basisAnzahlMessungen.value);
    }
    if (maschinenEinstellungenJson.present) {
      map['maschinen_einstellungen_json'] =
          Variable<String>(maschinenEinstellungenJson.value);
    }
    if (notizen.present) {
      map['notizen'] = Variable<String>(notizen.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (deletedAt.present) {
      map['deleted_at'] = Variable<DateTime>(deletedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ProductStepsCompanion(')
          ..write('id: $id, ')
          ..write('productId: $productId, ')
          ..write('reihenfolge: $reihenfolge, ')
          ..write('abteilung: $abteilung, ')
          ..write('basisMengeKg: $basisMengeKg, ')
          ..write('basisDauerMinuten: $basisDauerMinuten, ')
          ..write('fixZeitMinuten: $fixZeitMinuten, ')
          ..write('dauerStdAbweichung: $dauerStdAbweichung, ')
          ..write('basisMitarbeiter: $basisMitarbeiter, ')
          ..write('basisAnzahlMessungen: $basisAnzahlMessungen, ')
          ..write('maschinenEinstellungenJson: $maschinenEinstellungenJson, ')
          ..write('notizen: $notizen, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $RawMaterialsTable extends RawMaterials
    with TableInfo<$RawMaterialsTable, RawMaterial> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $RawMaterialsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
      'id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
      'name', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _artikelnummerMeta =
      const VerificationMeta('artikelnummer');
  @override
  late final GeneratedColumn<String> artikelnummer = GeneratedColumn<String>(
      'artikelnummer', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _einheitMeta =
      const VerificationMeta('einheit');
  @override
  late final GeneratedColumn<String> einheit = GeneratedColumn<String>(
      'einheit', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _lieferantMeta =
      const VerificationMeta('lieferant');
  @override
  late final GeneratedColumn<String> lieferant = GeneratedColumn<String>(
      'lieferant', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _leadTimeTageMeta =
      const VerificationMeta('leadTimeTage');
  @override
  late final GeneratedColumn<int> leadTimeTage = GeneratedColumn<int>(
      'lead_time_tage', aliasedName, true,
      type: DriftSqlType.int, requiredDuringInsert: false);
  static const VerificationMeta _chargenPflichtMeta =
      const VerificationMeta('chargenPflicht');
  @override
  late final GeneratedColumn<bool> chargenPflicht = GeneratedColumn<bool>(
      'chargen_pflicht', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints: GeneratedColumn.constraintIsAlways(
          'CHECK ("chargen_pflicht" IN (0, 1))'),
      defaultValue: const Constant(true));
  static const VerificationMeta _notizenMeta =
      const VerificationMeta('notizen');
  @override
  late final GeneratedColumn<String> notizen = GeneratedColumn<String>(
      'notizen', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _createdAtMeta =
      const VerificationMeta('createdAt');
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
      'created_at', aliasedName, false,
      type: DriftSqlType.dateTime,
      requiredDuringInsert: false,
      defaultValue: currentDateAndTime);
  static const VerificationMeta _updatedAtMeta =
      const VerificationMeta('updatedAt');
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
      'updated_at', aliasedName, false,
      type: DriftSqlType.dateTime,
      requiredDuringInsert: false,
      defaultValue: currentDateAndTime);
  static const VerificationMeta _deletedAtMeta =
      const VerificationMeta('deletedAt');
  @override
  late final GeneratedColumn<DateTime> deletedAt = GeneratedColumn<DateTime>(
      'deleted_at', aliasedName, true,
      type: DriftSqlType.dateTime, requiredDuringInsert: false);
  @override
  List<GeneratedColumn> get $columns => [
        id,
        name,
        artikelnummer,
        einheit,
        lieferant,
        leadTimeTage,
        chargenPflicht,
        notizen,
        createdAt,
        updatedAt,
        deletedAt
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'raw_materials';
  @override
  VerificationContext validateIntegrity(Insertable<RawMaterial> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
          _nameMeta, name.isAcceptableOrUnknown(data['name']!, _nameMeta));
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('artikelnummer')) {
      context.handle(
          _artikelnummerMeta,
          artikelnummer.isAcceptableOrUnknown(
              data['artikelnummer']!, _artikelnummerMeta));
    }
    if (data.containsKey('einheit')) {
      context.handle(_einheitMeta,
          einheit.isAcceptableOrUnknown(data['einheit']!, _einheitMeta));
    } else if (isInserting) {
      context.missing(_einheitMeta);
    }
    if (data.containsKey('lieferant')) {
      context.handle(_lieferantMeta,
          lieferant.isAcceptableOrUnknown(data['lieferant']!, _lieferantMeta));
    }
    if (data.containsKey('lead_time_tage')) {
      context.handle(
          _leadTimeTageMeta,
          leadTimeTage.isAcceptableOrUnknown(
              data['lead_time_tage']!, _leadTimeTageMeta));
    }
    if (data.containsKey('chargen_pflicht')) {
      context.handle(
          _chargenPflichtMeta,
          chargenPflicht.isAcceptableOrUnknown(
              data['chargen_pflicht']!, _chargenPflichtMeta));
    }
    if (data.containsKey('notizen')) {
      context.handle(_notizenMeta,
          notizen.isAcceptableOrUnknown(data['notizen']!, _notizenMeta));
    }
    if (data.containsKey('created_at')) {
      context.handle(_createdAtMeta,
          createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta));
    }
    if (data.containsKey('updated_at')) {
      context.handle(_updatedAtMeta,
          updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta));
    }
    if (data.containsKey('deleted_at')) {
      context.handle(_deletedAtMeta,
          deletedAt.isAcceptableOrUnknown(data['deleted_at']!, _deletedAtMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  RawMaterial map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return RawMaterial(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}id'])!,
      name: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}name'])!,
      artikelnummer: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}artikelnummer']),
      einheit: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}einheit'])!,
      lieferant: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}lieferant']),
      leadTimeTage: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}lead_time_tage']),
      chargenPflicht: attachedDatabase.typeMapping
          .read(DriftSqlType.bool, data['${effectivePrefix}chargen_pflicht'])!,
      notizen: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}notizen']),
      createdAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}created_at'])!,
      updatedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}updated_at'])!,
      deletedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}deleted_at']),
    );
  }

  @override
  $RawMaterialsTable createAlias(String alias) {
    return $RawMaterialsTable(attachedDatabase, alias);
  }
}

class RawMaterial extends DataClass implements Insertable<RawMaterial> {
  final String id;
  final String name;
  final String? artikelnummer;

  /// Basis-Einheit für Mengenangaben ("kg", "g", "l", "Stk").
  /// Wird nicht automatisch umgerechnet — alle Angaben müssen pro Rohware
  /// konsistent in dieser Einheit sein.
  final String einheit;
  final String? lieferant;

  /// Typische Lieferzeit in Tagen — für MRP-Bestelllogik (Phase 4).
  final int? leadTimeTage;

  /// Wenn true: Chargen-Tracking ist für diese Rohware verpflichtend (HACCP).
  /// Jeder Verbrauch muss dann auf eine konkrete Charge gebucht werden.
  final bool chargenPflicht;
  final String? notizen;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;
  const RawMaterial(
      {required this.id,
      required this.name,
      this.artikelnummer,
      required this.einheit,
      this.lieferant,
      this.leadTimeTage,
      required this.chargenPflicht,
      this.notizen,
      required this.createdAt,
      required this.updatedAt,
      this.deletedAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['name'] = Variable<String>(name);
    if (!nullToAbsent || artikelnummer != null) {
      map['artikelnummer'] = Variable<String>(artikelnummer);
    }
    map['einheit'] = Variable<String>(einheit);
    if (!nullToAbsent || lieferant != null) {
      map['lieferant'] = Variable<String>(lieferant);
    }
    if (!nullToAbsent || leadTimeTage != null) {
      map['lead_time_tage'] = Variable<int>(leadTimeTage);
    }
    map['chargen_pflicht'] = Variable<bool>(chargenPflicht);
    if (!nullToAbsent || notizen != null) {
      map['notizen'] = Variable<String>(notizen);
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    if (!nullToAbsent || deletedAt != null) {
      map['deleted_at'] = Variable<DateTime>(deletedAt);
    }
    return map;
  }

  RawMaterialsCompanion toCompanion(bool nullToAbsent) {
    return RawMaterialsCompanion(
      id: Value(id),
      name: Value(name),
      artikelnummer: artikelnummer == null && nullToAbsent
          ? const Value.absent()
          : Value(artikelnummer),
      einheit: Value(einheit),
      lieferant: lieferant == null && nullToAbsent
          ? const Value.absent()
          : Value(lieferant),
      leadTimeTage: leadTimeTage == null && nullToAbsent
          ? const Value.absent()
          : Value(leadTimeTage),
      chargenPflicht: Value(chargenPflicht),
      notizen: notizen == null && nullToAbsent
          ? const Value.absent()
          : Value(notizen),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
      deletedAt: deletedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(deletedAt),
    );
  }

  factory RawMaterial.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return RawMaterial(
      id: serializer.fromJson<String>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      artikelnummer: serializer.fromJson<String?>(json['artikelnummer']),
      einheit: serializer.fromJson<String>(json['einheit']),
      lieferant: serializer.fromJson<String?>(json['lieferant']),
      leadTimeTage: serializer.fromJson<int?>(json['leadTimeTage']),
      chargenPflicht: serializer.fromJson<bool>(json['chargenPflicht']),
      notizen: serializer.fromJson<String?>(json['notizen']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
      deletedAt: serializer.fromJson<DateTime?>(json['deletedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'name': serializer.toJson<String>(name),
      'artikelnummer': serializer.toJson<String?>(artikelnummer),
      'einheit': serializer.toJson<String>(einheit),
      'lieferant': serializer.toJson<String?>(lieferant),
      'leadTimeTage': serializer.toJson<int?>(leadTimeTage),
      'chargenPflicht': serializer.toJson<bool>(chargenPflicht),
      'notizen': serializer.toJson<String?>(notizen),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
      'deletedAt': serializer.toJson<DateTime?>(deletedAt),
    };
  }

  RawMaterial copyWith(
          {String? id,
          String? name,
          Value<String?> artikelnummer = const Value.absent(),
          String? einheit,
          Value<String?> lieferant = const Value.absent(),
          Value<int?> leadTimeTage = const Value.absent(),
          bool? chargenPflicht,
          Value<String?> notizen = const Value.absent(),
          DateTime? createdAt,
          DateTime? updatedAt,
          Value<DateTime?> deletedAt = const Value.absent()}) =>
      RawMaterial(
        id: id ?? this.id,
        name: name ?? this.name,
        artikelnummer:
            artikelnummer.present ? artikelnummer.value : this.artikelnummer,
        einheit: einheit ?? this.einheit,
        lieferant: lieferant.present ? lieferant.value : this.lieferant,
        leadTimeTage:
            leadTimeTage.present ? leadTimeTage.value : this.leadTimeTage,
        chargenPflicht: chargenPflicht ?? this.chargenPflicht,
        notizen: notizen.present ? notizen.value : this.notizen,
        createdAt: createdAt ?? this.createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
        deletedAt: deletedAt.present ? deletedAt.value : this.deletedAt,
      );
  RawMaterial copyWithCompanion(RawMaterialsCompanion data) {
    return RawMaterial(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      artikelnummer: data.artikelnummer.present
          ? data.artikelnummer.value
          : this.artikelnummer,
      einheit: data.einheit.present ? data.einheit.value : this.einheit,
      lieferant: data.lieferant.present ? data.lieferant.value : this.lieferant,
      leadTimeTage: data.leadTimeTage.present
          ? data.leadTimeTage.value
          : this.leadTimeTage,
      chargenPflicht: data.chargenPflicht.present
          ? data.chargenPflicht.value
          : this.chargenPflicht,
      notizen: data.notizen.present ? data.notizen.value : this.notizen,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      deletedAt: data.deletedAt.present ? data.deletedAt.value : this.deletedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('RawMaterial(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('artikelnummer: $artikelnummer, ')
          ..write('einheit: $einheit, ')
          ..write('lieferant: $lieferant, ')
          ..write('leadTimeTage: $leadTimeTage, ')
          ..write('chargenPflicht: $chargenPflicht, ')
          ..write('notizen: $notizen, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, name, artikelnummer, einheit, lieferant,
      leadTimeTage, chargenPflicht, notizen, createdAt, updatedAt, deletedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is RawMaterial &&
          other.id == this.id &&
          other.name == this.name &&
          other.artikelnummer == this.artikelnummer &&
          other.einheit == this.einheit &&
          other.lieferant == this.lieferant &&
          other.leadTimeTage == this.leadTimeTage &&
          other.chargenPflicht == this.chargenPflicht &&
          other.notizen == this.notizen &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt &&
          other.deletedAt == this.deletedAt);
}

class RawMaterialsCompanion extends UpdateCompanion<RawMaterial> {
  final Value<String> id;
  final Value<String> name;
  final Value<String?> artikelnummer;
  final Value<String> einheit;
  final Value<String?> lieferant;
  final Value<int?> leadTimeTage;
  final Value<bool> chargenPflicht;
  final Value<String?> notizen;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<DateTime?> deletedAt;
  final Value<int> rowid;
  const RawMaterialsCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.artikelnummer = const Value.absent(),
    this.einheit = const Value.absent(),
    this.lieferant = const Value.absent(),
    this.leadTimeTage = const Value.absent(),
    this.chargenPflicht = const Value.absent(),
    this.notizen = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  RawMaterialsCompanion.insert({
    required String id,
    required String name,
    this.artikelnummer = const Value.absent(),
    required String einheit,
    this.lieferant = const Value.absent(),
    this.leadTimeTage = const Value.absent(),
    this.chargenPflicht = const Value.absent(),
    this.notizen = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  })  : id = Value(id),
        name = Value(name),
        einheit = Value(einheit);
  static Insertable<RawMaterial> custom({
    Expression<String>? id,
    Expression<String>? name,
    Expression<String>? artikelnummer,
    Expression<String>? einheit,
    Expression<String>? lieferant,
    Expression<int>? leadTimeTage,
    Expression<bool>? chargenPflicht,
    Expression<String>? notizen,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<DateTime>? deletedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (artikelnummer != null) 'artikelnummer': artikelnummer,
      if (einheit != null) 'einheit': einheit,
      if (lieferant != null) 'lieferant': lieferant,
      if (leadTimeTage != null) 'lead_time_tage': leadTimeTage,
      if (chargenPflicht != null) 'chargen_pflicht': chargenPflicht,
      if (notizen != null) 'notizen': notizen,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (deletedAt != null) 'deleted_at': deletedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  RawMaterialsCompanion copyWith(
      {Value<String>? id,
      Value<String>? name,
      Value<String?>? artikelnummer,
      Value<String>? einheit,
      Value<String?>? lieferant,
      Value<int?>? leadTimeTage,
      Value<bool>? chargenPflicht,
      Value<String?>? notizen,
      Value<DateTime>? createdAt,
      Value<DateTime>? updatedAt,
      Value<DateTime?>? deletedAt,
      Value<int>? rowid}) {
    return RawMaterialsCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      artikelnummer: artikelnummer ?? this.artikelnummer,
      einheit: einheit ?? this.einheit,
      lieferant: lieferant ?? this.lieferant,
      leadTimeTage: leadTimeTage ?? this.leadTimeTage,
      chargenPflicht: chargenPflicht ?? this.chargenPflicht,
      notizen: notizen ?? this.notizen,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: deletedAt ?? this.deletedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (artikelnummer.present) {
      map['artikelnummer'] = Variable<String>(artikelnummer.value);
    }
    if (einheit.present) {
      map['einheit'] = Variable<String>(einheit.value);
    }
    if (lieferant.present) {
      map['lieferant'] = Variable<String>(lieferant.value);
    }
    if (leadTimeTage.present) {
      map['lead_time_tage'] = Variable<int>(leadTimeTage.value);
    }
    if (chargenPflicht.present) {
      map['chargen_pflicht'] = Variable<bool>(chargenPflicht.value);
    }
    if (notizen.present) {
      map['notizen'] = Variable<String>(notizen.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (deletedAt.present) {
      map['deleted_at'] = Variable<DateTime>(deletedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('RawMaterialsCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('artikelnummer: $artikelnummer, ')
          ..write('einheit: $einheit, ')
          ..write('lieferant: $lieferant, ')
          ..write('leadTimeTage: $leadTimeTage, ')
          ..write('chargenPflicht: $chargenPflicht, ')
          ..write('notizen: $notizen, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ProductRawMaterialsTable extends ProductRawMaterials
    with TableInfo<$ProductRawMaterialsTable, ProductRawMaterial> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ProductRawMaterialsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
      'id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _productIdMeta =
      const VerificationMeta('productId');
  @override
  late final GeneratedColumn<String> productId = GeneratedColumn<String>(
      'product_id', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: true,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('REFERENCES products (id)'));
  static const VerificationMeta _rawMaterialIdMeta =
      const VerificationMeta('rawMaterialId');
  @override
  late final GeneratedColumn<String> rawMaterialId = GeneratedColumn<String>(
      'raw_material_id', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: true,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('REFERENCES raw_materials (id)'));
  static const VerificationMeta _mengeProKgProduktMeta =
      const VerificationMeta('mengeProKgProdukt');
  @override
  late final GeneratedColumn<double> mengeProKgProdukt =
      GeneratedColumn<double>('menge_pro_kg_produkt', aliasedName, false,
          type: DriftSqlType.double, requiredDuringInsert: true);
  static const VerificationMeta _toleranzProzentMeta =
      const VerificationMeta('toleranzProzent');
  @override
  late final GeneratedColumn<double> toleranzProzent = GeneratedColumn<double>(
      'toleranz_prozent', aliasedName, true,
      type: DriftSqlType.double, requiredDuringInsert: false);
  static const VerificationMeta _notizenMeta =
      const VerificationMeta('notizen');
  @override
  late final GeneratedColumn<String> notizen = GeneratedColumn<String>(
      'notizen', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _createdAtMeta =
      const VerificationMeta('createdAt');
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
      'created_at', aliasedName, false,
      type: DriftSqlType.dateTime,
      requiredDuringInsert: false,
      defaultValue: currentDateAndTime);
  static const VerificationMeta _updatedAtMeta =
      const VerificationMeta('updatedAt');
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
      'updated_at', aliasedName, false,
      type: DriftSqlType.dateTime,
      requiredDuringInsert: false,
      defaultValue: currentDateAndTime);
  static const VerificationMeta _deletedAtMeta =
      const VerificationMeta('deletedAt');
  @override
  late final GeneratedColumn<DateTime> deletedAt = GeneratedColumn<DateTime>(
      'deleted_at', aliasedName, true,
      type: DriftSqlType.dateTime, requiredDuringInsert: false);
  @override
  List<GeneratedColumn> get $columns => [
        id,
        productId,
        rawMaterialId,
        mengeProKgProdukt,
        toleranzProzent,
        notizen,
        createdAt,
        updatedAt,
        deletedAt
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'product_raw_materials';
  @override
  VerificationContext validateIntegrity(Insertable<ProductRawMaterial> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('product_id')) {
      context.handle(_productIdMeta,
          productId.isAcceptableOrUnknown(data['product_id']!, _productIdMeta));
    } else if (isInserting) {
      context.missing(_productIdMeta);
    }
    if (data.containsKey('raw_material_id')) {
      context.handle(
          _rawMaterialIdMeta,
          rawMaterialId.isAcceptableOrUnknown(
              data['raw_material_id']!, _rawMaterialIdMeta));
    } else if (isInserting) {
      context.missing(_rawMaterialIdMeta);
    }
    if (data.containsKey('menge_pro_kg_produkt')) {
      context.handle(
          _mengeProKgProduktMeta,
          mengeProKgProdukt.isAcceptableOrUnknown(
              data['menge_pro_kg_produkt']!, _mengeProKgProduktMeta));
    } else if (isInserting) {
      context.missing(_mengeProKgProduktMeta);
    }
    if (data.containsKey('toleranz_prozent')) {
      context.handle(
          _toleranzProzentMeta,
          toleranzProzent.isAcceptableOrUnknown(
              data['toleranz_prozent']!, _toleranzProzentMeta));
    }
    if (data.containsKey('notizen')) {
      context.handle(_notizenMeta,
          notizen.isAcceptableOrUnknown(data['notizen']!, _notizenMeta));
    }
    if (data.containsKey('created_at')) {
      context.handle(_createdAtMeta,
          createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta));
    }
    if (data.containsKey('updated_at')) {
      context.handle(_updatedAtMeta,
          updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta));
    }
    if (data.containsKey('deleted_at')) {
      context.handle(_deletedAtMeta,
          deletedAt.isAcceptableOrUnknown(data['deleted_at']!, _deletedAtMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  ProductRawMaterial map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ProductRawMaterial(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}id'])!,
      productId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}product_id'])!,
      rawMaterialId: attachedDatabase.typeMapping.read(
          DriftSqlType.string, data['${effectivePrefix}raw_material_id'])!,
      mengeProKgProdukt: attachedDatabase.typeMapping.read(
          DriftSqlType.double, data['${effectivePrefix}menge_pro_kg_produkt'])!,
      toleranzProzent: attachedDatabase.typeMapping.read(
          DriftSqlType.double, data['${effectivePrefix}toleranz_prozent']),
      notizen: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}notizen']),
      createdAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}created_at'])!,
      updatedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}updated_at'])!,
      deletedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}deleted_at']),
    );
  }

  @override
  $ProductRawMaterialsTable createAlias(String alias) {
    return $ProductRawMaterialsTable(attachedDatabase, alias);
  }
}

class ProductRawMaterial extends DataClass
    implements Insertable<ProductRawMaterial> {
  final String id;
  final String productId;
  final String rawMaterialId;

  /// Menge der Rohware pro 1 kg Fertigprodukt.
  /// Einheit ergibt sich aus [RawMaterials.einheit].
  final double mengeProKgProdukt;

  /// Optional: prozentuale Toleranz (z.B. 5.0 = ±5%). Reserviert für Phase 4+.
  final double? toleranzProzent;
  final String? notizen;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;
  const ProductRawMaterial(
      {required this.id,
      required this.productId,
      required this.rawMaterialId,
      required this.mengeProKgProdukt,
      this.toleranzProzent,
      this.notizen,
      required this.createdAt,
      required this.updatedAt,
      this.deletedAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['product_id'] = Variable<String>(productId);
    map['raw_material_id'] = Variable<String>(rawMaterialId);
    map['menge_pro_kg_produkt'] = Variable<double>(mengeProKgProdukt);
    if (!nullToAbsent || toleranzProzent != null) {
      map['toleranz_prozent'] = Variable<double>(toleranzProzent);
    }
    if (!nullToAbsent || notizen != null) {
      map['notizen'] = Variable<String>(notizen);
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    if (!nullToAbsent || deletedAt != null) {
      map['deleted_at'] = Variable<DateTime>(deletedAt);
    }
    return map;
  }

  ProductRawMaterialsCompanion toCompanion(bool nullToAbsent) {
    return ProductRawMaterialsCompanion(
      id: Value(id),
      productId: Value(productId),
      rawMaterialId: Value(rawMaterialId),
      mengeProKgProdukt: Value(mengeProKgProdukt),
      toleranzProzent: toleranzProzent == null && nullToAbsent
          ? const Value.absent()
          : Value(toleranzProzent),
      notizen: notizen == null && nullToAbsent
          ? const Value.absent()
          : Value(notizen),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
      deletedAt: deletedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(deletedAt),
    );
  }

  factory ProductRawMaterial.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ProductRawMaterial(
      id: serializer.fromJson<String>(json['id']),
      productId: serializer.fromJson<String>(json['productId']),
      rawMaterialId: serializer.fromJson<String>(json['rawMaterialId']),
      mengeProKgProdukt: serializer.fromJson<double>(json['mengeProKgProdukt']),
      toleranzProzent: serializer.fromJson<double?>(json['toleranzProzent']),
      notizen: serializer.fromJson<String?>(json['notizen']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
      deletedAt: serializer.fromJson<DateTime?>(json['deletedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'productId': serializer.toJson<String>(productId),
      'rawMaterialId': serializer.toJson<String>(rawMaterialId),
      'mengeProKgProdukt': serializer.toJson<double>(mengeProKgProdukt),
      'toleranzProzent': serializer.toJson<double?>(toleranzProzent),
      'notizen': serializer.toJson<String?>(notizen),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
      'deletedAt': serializer.toJson<DateTime?>(deletedAt),
    };
  }

  ProductRawMaterial copyWith(
          {String? id,
          String? productId,
          String? rawMaterialId,
          double? mengeProKgProdukt,
          Value<double?> toleranzProzent = const Value.absent(),
          Value<String?> notizen = const Value.absent(),
          DateTime? createdAt,
          DateTime? updatedAt,
          Value<DateTime?> deletedAt = const Value.absent()}) =>
      ProductRawMaterial(
        id: id ?? this.id,
        productId: productId ?? this.productId,
        rawMaterialId: rawMaterialId ?? this.rawMaterialId,
        mengeProKgProdukt: mengeProKgProdukt ?? this.mengeProKgProdukt,
        toleranzProzent: toleranzProzent.present
            ? toleranzProzent.value
            : this.toleranzProzent,
        notizen: notizen.present ? notizen.value : this.notizen,
        createdAt: createdAt ?? this.createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
        deletedAt: deletedAt.present ? deletedAt.value : this.deletedAt,
      );
  ProductRawMaterial copyWithCompanion(ProductRawMaterialsCompanion data) {
    return ProductRawMaterial(
      id: data.id.present ? data.id.value : this.id,
      productId: data.productId.present ? data.productId.value : this.productId,
      rawMaterialId: data.rawMaterialId.present
          ? data.rawMaterialId.value
          : this.rawMaterialId,
      mengeProKgProdukt: data.mengeProKgProdukt.present
          ? data.mengeProKgProdukt.value
          : this.mengeProKgProdukt,
      toleranzProzent: data.toleranzProzent.present
          ? data.toleranzProzent.value
          : this.toleranzProzent,
      notizen: data.notizen.present ? data.notizen.value : this.notizen,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      deletedAt: data.deletedAt.present ? data.deletedAt.value : this.deletedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ProductRawMaterial(')
          ..write('id: $id, ')
          ..write('productId: $productId, ')
          ..write('rawMaterialId: $rawMaterialId, ')
          ..write('mengeProKgProdukt: $mengeProKgProdukt, ')
          ..write('toleranzProzent: $toleranzProzent, ')
          ..write('notizen: $notizen, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
      id,
      productId,
      rawMaterialId,
      mengeProKgProdukt,
      toleranzProzent,
      notizen,
      createdAt,
      updatedAt,
      deletedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ProductRawMaterial &&
          other.id == this.id &&
          other.productId == this.productId &&
          other.rawMaterialId == this.rawMaterialId &&
          other.mengeProKgProdukt == this.mengeProKgProdukt &&
          other.toleranzProzent == this.toleranzProzent &&
          other.notizen == this.notizen &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt &&
          other.deletedAt == this.deletedAt);
}

class ProductRawMaterialsCompanion extends UpdateCompanion<ProductRawMaterial> {
  final Value<String> id;
  final Value<String> productId;
  final Value<String> rawMaterialId;
  final Value<double> mengeProKgProdukt;
  final Value<double?> toleranzProzent;
  final Value<String?> notizen;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<DateTime?> deletedAt;
  final Value<int> rowid;
  const ProductRawMaterialsCompanion({
    this.id = const Value.absent(),
    this.productId = const Value.absent(),
    this.rawMaterialId = const Value.absent(),
    this.mengeProKgProdukt = const Value.absent(),
    this.toleranzProzent = const Value.absent(),
    this.notizen = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ProductRawMaterialsCompanion.insert({
    required String id,
    required String productId,
    required String rawMaterialId,
    required double mengeProKgProdukt,
    this.toleranzProzent = const Value.absent(),
    this.notizen = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  })  : id = Value(id),
        productId = Value(productId),
        rawMaterialId = Value(rawMaterialId),
        mengeProKgProdukt = Value(mengeProKgProdukt);
  static Insertable<ProductRawMaterial> custom({
    Expression<String>? id,
    Expression<String>? productId,
    Expression<String>? rawMaterialId,
    Expression<double>? mengeProKgProdukt,
    Expression<double>? toleranzProzent,
    Expression<String>? notizen,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<DateTime>? deletedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (productId != null) 'product_id': productId,
      if (rawMaterialId != null) 'raw_material_id': rawMaterialId,
      if (mengeProKgProdukt != null) 'menge_pro_kg_produkt': mengeProKgProdukt,
      if (toleranzProzent != null) 'toleranz_prozent': toleranzProzent,
      if (notizen != null) 'notizen': notizen,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (deletedAt != null) 'deleted_at': deletedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ProductRawMaterialsCompanion copyWith(
      {Value<String>? id,
      Value<String>? productId,
      Value<String>? rawMaterialId,
      Value<double>? mengeProKgProdukt,
      Value<double?>? toleranzProzent,
      Value<String?>? notizen,
      Value<DateTime>? createdAt,
      Value<DateTime>? updatedAt,
      Value<DateTime?>? deletedAt,
      Value<int>? rowid}) {
    return ProductRawMaterialsCompanion(
      id: id ?? this.id,
      productId: productId ?? this.productId,
      rawMaterialId: rawMaterialId ?? this.rawMaterialId,
      mengeProKgProdukt: mengeProKgProdukt ?? this.mengeProKgProdukt,
      toleranzProzent: toleranzProzent ?? this.toleranzProzent,
      notizen: notizen ?? this.notizen,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: deletedAt ?? this.deletedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (productId.present) {
      map['product_id'] = Variable<String>(productId.value);
    }
    if (rawMaterialId.present) {
      map['raw_material_id'] = Variable<String>(rawMaterialId.value);
    }
    if (mengeProKgProdukt.present) {
      map['menge_pro_kg_produkt'] = Variable<double>(mengeProKgProdukt.value);
    }
    if (toleranzProzent.present) {
      map['toleranz_prozent'] = Variable<double>(toleranzProzent.value);
    }
    if (notizen.present) {
      map['notizen'] = Variable<String>(notizen.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (deletedAt.present) {
      map['deleted_at'] = Variable<DateTime>(deletedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ProductRawMaterialsCompanion(')
          ..write('id: $id, ')
          ..write('productId: $productId, ')
          ..write('rawMaterialId: $rawMaterialId, ')
          ..write('mengeProKgProdukt: $mengeProKgProdukt, ')
          ..write('toleranzProzent: $toleranzProzent, ')
          ..write('notizen: $notizen, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $RawMaterialBatchesTable extends RawMaterialBatches
    with TableInfo<$RawMaterialBatchesTable, RawMaterialBatche> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $RawMaterialBatchesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
      'id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _rawMaterialIdMeta =
      const VerificationMeta('rawMaterialId');
  @override
  late final GeneratedColumn<String> rawMaterialId = GeneratedColumn<String>(
      'raw_material_id', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: true,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('REFERENCES raw_materials (id)'));
  static const VerificationMeta _chargennummerMeta =
      const VerificationMeta('chargennummer');
  @override
  late final GeneratedColumn<String> chargennummer = GeneratedColumn<String>(
      'chargennummer', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _mhdMeta = const VerificationMeta('mhd');
  @override
  late final GeneratedColumn<DateTime> mhd = GeneratedColumn<DateTime>(
      'mhd', aliasedName, true,
      type: DriftSqlType.dateTime, requiredDuringInsert: false);
  static const VerificationMeta _eingangsDatumMeta =
      const VerificationMeta('eingangsDatum');
  @override
  late final GeneratedColumn<DateTime> eingangsDatum =
      GeneratedColumn<DateTime>('eingangs_datum', aliasedName, false,
          type: DriftSqlType.dateTime, requiredDuringInsert: true);
  static const VerificationMeta _mengeInitialMeta =
      const VerificationMeta('mengeInitial');
  @override
  late final GeneratedColumn<double> mengeInitial = GeneratedColumn<double>(
      'menge_initial', aliasedName, false,
      type: DriftSqlType.double, requiredDuringInsert: true);
  static const VerificationMeta _mengeAktuellMeta =
      const VerificationMeta('mengeAktuell');
  @override
  late final GeneratedColumn<double> mengeAktuell = GeneratedColumn<double>(
      'menge_aktuell', aliasedName, false,
      type: DriftSqlType.double, requiredDuringInsert: true);
  static const VerificationMeta _einheitMeta =
      const VerificationMeta('einheit');
  @override
  late final GeneratedColumn<String> einheit = GeneratedColumn<String>(
      'einheit', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _lieferantMeta =
      const VerificationMeta('lieferant');
  @override
  late final GeneratedColumn<String> lieferant = GeneratedColumn<String>(
      'lieferant', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _notizenMeta =
      const VerificationMeta('notizen');
  @override
  late final GeneratedColumn<String> notizen = GeneratedColumn<String>(
      'notizen', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _createdAtMeta =
      const VerificationMeta('createdAt');
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
      'created_at', aliasedName, false,
      type: DriftSqlType.dateTime,
      requiredDuringInsert: false,
      defaultValue: currentDateAndTime);
  static const VerificationMeta _updatedAtMeta =
      const VerificationMeta('updatedAt');
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
      'updated_at', aliasedName, false,
      type: DriftSqlType.dateTime,
      requiredDuringInsert: false,
      defaultValue: currentDateAndTime);
  static const VerificationMeta _deletedAtMeta =
      const VerificationMeta('deletedAt');
  @override
  late final GeneratedColumn<DateTime> deletedAt = GeneratedColumn<DateTime>(
      'deleted_at', aliasedName, true,
      type: DriftSqlType.dateTime, requiredDuringInsert: false);
  @override
  List<GeneratedColumn> get $columns => [
        id,
        rawMaterialId,
        chargennummer,
        mhd,
        eingangsDatum,
        mengeInitial,
        mengeAktuell,
        einheit,
        lieferant,
        notizen,
        createdAt,
        updatedAt,
        deletedAt
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'raw_material_batches';
  @override
  VerificationContext validateIntegrity(Insertable<RawMaterialBatche> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('raw_material_id')) {
      context.handle(
          _rawMaterialIdMeta,
          rawMaterialId.isAcceptableOrUnknown(
              data['raw_material_id']!, _rawMaterialIdMeta));
    } else if (isInserting) {
      context.missing(_rawMaterialIdMeta);
    }
    if (data.containsKey('chargennummer')) {
      context.handle(
          _chargennummerMeta,
          chargennummer.isAcceptableOrUnknown(
              data['chargennummer']!, _chargennummerMeta));
    } else if (isInserting) {
      context.missing(_chargennummerMeta);
    }
    if (data.containsKey('mhd')) {
      context.handle(
          _mhdMeta, mhd.isAcceptableOrUnknown(data['mhd']!, _mhdMeta));
    }
    if (data.containsKey('eingangs_datum')) {
      context.handle(
          _eingangsDatumMeta,
          eingangsDatum.isAcceptableOrUnknown(
              data['eingangs_datum']!, _eingangsDatumMeta));
    } else if (isInserting) {
      context.missing(_eingangsDatumMeta);
    }
    if (data.containsKey('menge_initial')) {
      context.handle(
          _mengeInitialMeta,
          mengeInitial.isAcceptableOrUnknown(
              data['menge_initial']!, _mengeInitialMeta));
    } else if (isInserting) {
      context.missing(_mengeInitialMeta);
    }
    if (data.containsKey('menge_aktuell')) {
      context.handle(
          _mengeAktuellMeta,
          mengeAktuell.isAcceptableOrUnknown(
              data['menge_aktuell']!, _mengeAktuellMeta));
    } else if (isInserting) {
      context.missing(_mengeAktuellMeta);
    }
    if (data.containsKey('einheit')) {
      context.handle(_einheitMeta,
          einheit.isAcceptableOrUnknown(data['einheit']!, _einheitMeta));
    } else if (isInserting) {
      context.missing(_einheitMeta);
    }
    if (data.containsKey('lieferant')) {
      context.handle(_lieferantMeta,
          lieferant.isAcceptableOrUnknown(data['lieferant']!, _lieferantMeta));
    }
    if (data.containsKey('notizen')) {
      context.handle(_notizenMeta,
          notizen.isAcceptableOrUnknown(data['notizen']!, _notizenMeta));
    }
    if (data.containsKey('created_at')) {
      context.handle(_createdAtMeta,
          createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta));
    }
    if (data.containsKey('updated_at')) {
      context.handle(_updatedAtMeta,
          updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta));
    }
    if (data.containsKey('deleted_at')) {
      context.handle(_deletedAtMeta,
          deletedAt.isAcceptableOrUnknown(data['deleted_at']!, _deletedAtMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  RawMaterialBatche map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return RawMaterialBatche(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}id'])!,
      rawMaterialId: attachedDatabase.typeMapping.read(
          DriftSqlType.string, data['${effectivePrefix}raw_material_id'])!,
      chargennummer: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}chargennummer'])!,
      mhd: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}mhd']),
      eingangsDatum: attachedDatabase.typeMapping.read(
          DriftSqlType.dateTime, data['${effectivePrefix}eingangs_datum'])!,
      mengeInitial: attachedDatabase.typeMapping
          .read(DriftSqlType.double, data['${effectivePrefix}menge_initial'])!,
      mengeAktuell: attachedDatabase.typeMapping
          .read(DriftSqlType.double, data['${effectivePrefix}menge_aktuell'])!,
      einheit: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}einheit'])!,
      lieferant: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}lieferant']),
      notizen: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}notizen']),
      createdAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}created_at'])!,
      updatedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}updated_at'])!,
      deletedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}deleted_at']),
    );
  }

  @override
  $RawMaterialBatchesTable createAlias(String alias) {
    return $RawMaterialBatchesTable(attachedDatabase, alias);
  }
}

class RawMaterialBatche extends DataClass
    implements Insertable<RawMaterialBatche> {
  final String id;
  final String rawMaterialId;

  /// Chargennummer vom Lieferanten (wie auf dem Lieferschein).
  final String chargennummer;

  /// Mindesthaltbarkeitsdatum. Nullable, weil nicht jede Rohware eins hat.
  final DateTime? mhd;

  /// Wann die Charge ins Lager kam.
  final DateTime eingangsDatum;

  /// Ursprünglich gelieferte Menge (bleibt konstant, historisch).
  final double mengeInitial;

  /// Aktuell noch verfügbare Menge in der Charge. Wird bei jedem Verbrauch
  /// durch einen ProductionRun dekrementiert. Bei 0 ist die Charge leer,
  /// wird aber **nicht gelöscht** (HACCP-Nachvollziehbarkeit).
  final double mengeAktuell;

  /// Einheit — denormalisiert aus [RawMaterials.einheit], damit historische
  /// Chargen ihre Einheit behalten, falls sich die Stammdaten ändern.
  final String einheit;
  final String? lieferant;
  final String? notizen;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;
  const RawMaterialBatche(
      {required this.id,
      required this.rawMaterialId,
      required this.chargennummer,
      this.mhd,
      required this.eingangsDatum,
      required this.mengeInitial,
      required this.mengeAktuell,
      required this.einheit,
      this.lieferant,
      this.notizen,
      required this.createdAt,
      required this.updatedAt,
      this.deletedAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['raw_material_id'] = Variable<String>(rawMaterialId);
    map['chargennummer'] = Variable<String>(chargennummer);
    if (!nullToAbsent || mhd != null) {
      map['mhd'] = Variable<DateTime>(mhd);
    }
    map['eingangs_datum'] = Variable<DateTime>(eingangsDatum);
    map['menge_initial'] = Variable<double>(mengeInitial);
    map['menge_aktuell'] = Variable<double>(mengeAktuell);
    map['einheit'] = Variable<String>(einheit);
    if (!nullToAbsent || lieferant != null) {
      map['lieferant'] = Variable<String>(lieferant);
    }
    if (!nullToAbsent || notizen != null) {
      map['notizen'] = Variable<String>(notizen);
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    if (!nullToAbsent || deletedAt != null) {
      map['deleted_at'] = Variable<DateTime>(deletedAt);
    }
    return map;
  }

  RawMaterialBatchesCompanion toCompanion(bool nullToAbsent) {
    return RawMaterialBatchesCompanion(
      id: Value(id),
      rawMaterialId: Value(rawMaterialId),
      chargennummer: Value(chargennummer),
      mhd: mhd == null && nullToAbsent ? const Value.absent() : Value(mhd),
      eingangsDatum: Value(eingangsDatum),
      mengeInitial: Value(mengeInitial),
      mengeAktuell: Value(mengeAktuell),
      einheit: Value(einheit),
      lieferant: lieferant == null && nullToAbsent
          ? const Value.absent()
          : Value(lieferant),
      notizen: notizen == null && nullToAbsent
          ? const Value.absent()
          : Value(notizen),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
      deletedAt: deletedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(deletedAt),
    );
  }

  factory RawMaterialBatche.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return RawMaterialBatche(
      id: serializer.fromJson<String>(json['id']),
      rawMaterialId: serializer.fromJson<String>(json['rawMaterialId']),
      chargennummer: serializer.fromJson<String>(json['chargennummer']),
      mhd: serializer.fromJson<DateTime?>(json['mhd']),
      eingangsDatum: serializer.fromJson<DateTime>(json['eingangsDatum']),
      mengeInitial: serializer.fromJson<double>(json['mengeInitial']),
      mengeAktuell: serializer.fromJson<double>(json['mengeAktuell']),
      einheit: serializer.fromJson<String>(json['einheit']),
      lieferant: serializer.fromJson<String?>(json['lieferant']),
      notizen: serializer.fromJson<String?>(json['notizen']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
      deletedAt: serializer.fromJson<DateTime?>(json['deletedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'rawMaterialId': serializer.toJson<String>(rawMaterialId),
      'chargennummer': serializer.toJson<String>(chargennummer),
      'mhd': serializer.toJson<DateTime?>(mhd),
      'eingangsDatum': serializer.toJson<DateTime>(eingangsDatum),
      'mengeInitial': serializer.toJson<double>(mengeInitial),
      'mengeAktuell': serializer.toJson<double>(mengeAktuell),
      'einheit': serializer.toJson<String>(einheit),
      'lieferant': serializer.toJson<String?>(lieferant),
      'notizen': serializer.toJson<String?>(notizen),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
      'deletedAt': serializer.toJson<DateTime?>(deletedAt),
    };
  }

  RawMaterialBatche copyWith(
          {String? id,
          String? rawMaterialId,
          String? chargennummer,
          Value<DateTime?> mhd = const Value.absent(),
          DateTime? eingangsDatum,
          double? mengeInitial,
          double? mengeAktuell,
          String? einheit,
          Value<String?> lieferant = const Value.absent(),
          Value<String?> notizen = const Value.absent(),
          DateTime? createdAt,
          DateTime? updatedAt,
          Value<DateTime?> deletedAt = const Value.absent()}) =>
      RawMaterialBatche(
        id: id ?? this.id,
        rawMaterialId: rawMaterialId ?? this.rawMaterialId,
        chargennummer: chargennummer ?? this.chargennummer,
        mhd: mhd.present ? mhd.value : this.mhd,
        eingangsDatum: eingangsDatum ?? this.eingangsDatum,
        mengeInitial: mengeInitial ?? this.mengeInitial,
        mengeAktuell: mengeAktuell ?? this.mengeAktuell,
        einheit: einheit ?? this.einheit,
        lieferant: lieferant.present ? lieferant.value : this.lieferant,
        notizen: notizen.present ? notizen.value : this.notizen,
        createdAt: createdAt ?? this.createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
        deletedAt: deletedAt.present ? deletedAt.value : this.deletedAt,
      );
  RawMaterialBatche copyWithCompanion(RawMaterialBatchesCompanion data) {
    return RawMaterialBatche(
      id: data.id.present ? data.id.value : this.id,
      rawMaterialId: data.rawMaterialId.present
          ? data.rawMaterialId.value
          : this.rawMaterialId,
      chargennummer: data.chargennummer.present
          ? data.chargennummer.value
          : this.chargennummer,
      mhd: data.mhd.present ? data.mhd.value : this.mhd,
      eingangsDatum: data.eingangsDatum.present
          ? data.eingangsDatum.value
          : this.eingangsDatum,
      mengeInitial: data.mengeInitial.present
          ? data.mengeInitial.value
          : this.mengeInitial,
      mengeAktuell: data.mengeAktuell.present
          ? data.mengeAktuell.value
          : this.mengeAktuell,
      einheit: data.einheit.present ? data.einheit.value : this.einheit,
      lieferant: data.lieferant.present ? data.lieferant.value : this.lieferant,
      notizen: data.notizen.present ? data.notizen.value : this.notizen,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      deletedAt: data.deletedAt.present ? data.deletedAt.value : this.deletedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('RawMaterialBatche(')
          ..write('id: $id, ')
          ..write('rawMaterialId: $rawMaterialId, ')
          ..write('chargennummer: $chargennummer, ')
          ..write('mhd: $mhd, ')
          ..write('eingangsDatum: $eingangsDatum, ')
          ..write('mengeInitial: $mengeInitial, ')
          ..write('mengeAktuell: $mengeAktuell, ')
          ..write('einheit: $einheit, ')
          ..write('lieferant: $lieferant, ')
          ..write('notizen: $notizen, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
      id,
      rawMaterialId,
      chargennummer,
      mhd,
      eingangsDatum,
      mengeInitial,
      mengeAktuell,
      einheit,
      lieferant,
      notizen,
      createdAt,
      updatedAt,
      deletedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is RawMaterialBatche &&
          other.id == this.id &&
          other.rawMaterialId == this.rawMaterialId &&
          other.chargennummer == this.chargennummer &&
          other.mhd == this.mhd &&
          other.eingangsDatum == this.eingangsDatum &&
          other.mengeInitial == this.mengeInitial &&
          other.mengeAktuell == this.mengeAktuell &&
          other.einheit == this.einheit &&
          other.lieferant == this.lieferant &&
          other.notizen == this.notizen &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt &&
          other.deletedAt == this.deletedAt);
}

class RawMaterialBatchesCompanion extends UpdateCompanion<RawMaterialBatche> {
  final Value<String> id;
  final Value<String> rawMaterialId;
  final Value<String> chargennummer;
  final Value<DateTime?> mhd;
  final Value<DateTime> eingangsDatum;
  final Value<double> mengeInitial;
  final Value<double> mengeAktuell;
  final Value<String> einheit;
  final Value<String?> lieferant;
  final Value<String?> notizen;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<DateTime?> deletedAt;
  final Value<int> rowid;
  const RawMaterialBatchesCompanion({
    this.id = const Value.absent(),
    this.rawMaterialId = const Value.absent(),
    this.chargennummer = const Value.absent(),
    this.mhd = const Value.absent(),
    this.eingangsDatum = const Value.absent(),
    this.mengeInitial = const Value.absent(),
    this.mengeAktuell = const Value.absent(),
    this.einheit = const Value.absent(),
    this.lieferant = const Value.absent(),
    this.notizen = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  RawMaterialBatchesCompanion.insert({
    required String id,
    required String rawMaterialId,
    required String chargennummer,
    this.mhd = const Value.absent(),
    required DateTime eingangsDatum,
    required double mengeInitial,
    required double mengeAktuell,
    required String einheit,
    this.lieferant = const Value.absent(),
    this.notizen = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  })  : id = Value(id),
        rawMaterialId = Value(rawMaterialId),
        chargennummer = Value(chargennummer),
        eingangsDatum = Value(eingangsDatum),
        mengeInitial = Value(mengeInitial),
        mengeAktuell = Value(mengeAktuell),
        einheit = Value(einheit);
  static Insertable<RawMaterialBatche> custom({
    Expression<String>? id,
    Expression<String>? rawMaterialId,
    Expression<String>? chargennummer,
    Expression<DateTime>? mhd,
    Expression<DateTime>? eingangsDatum,
    Expression<double>? mengeInitial,
    Expression<double>? mengeAktuell,
    Expression<String>? einheit,
    Expression<String>? lieferant,
    Expression<String>? notizen,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<DateTime>? deletedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (rawMaterialId != null) 'raw_material_id': rawMaterialId,
      if (chargennummer != null) 'chargennummer': chargennummer,
      if (mhd != null) 'mhd': mhd,
      if (eingangsDatum != null) 'eingangs_datum': eingangsDatum,
      if (mengeInitial != null) 'menge_initial': mengeInitial,
      if (mengeAktuell != null) 'menge_aktuell': mengeAktuell,
      if (einheit != null) 'einheit': einheit,
      if (lieferant != null) 'lieferant': lieferant,
      if (notizen != null) 'notizen': notizen,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (deletedAt != null) 'deleted_at': deletedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  RawMaterialBatchesCompanion copyWith(
      {Value<String>? id,
      Value<String>? rawMaterialId,
      Value<String>? chargennummer,
      Value<DateTime?>? mhd,
      Value<DateTime>? eingangsDatum,
      Value<double>? mengeInitial,
      Value<double>? mengeAktuell,
      Value<String>? einheit,
      Value<String?>? lieferant,
      Value<String?>? notizen,
      Value<DateTime>? createdAt,
      Value<DateTime>? updatedAt,
      Value<DateTime?>? deletedAt,
      Value<int>? rowid}) {
    return RawMaterialBatchesCompanion(
      id: id ?? this.id,
      rawMaterialId: rawMaterialId ?? this.rawMaterialId,
      chargennummer: chargennummer ?? this.chargennummer,
      mhd: mhd ?? this.mhd,
      eingangsDatum: eingangsDatum ?? this.eingangsDatum,
      mengeInitial: mengeInitial ?? this.mengeInitial,
      mengeAktuell: mengeAktuell ?? this.mengeAktuell,
      einheit: einheit ?? this.einheit,
      lieferant: lieferant ?? this.lieferant,
      notizen: notizen ?? this.notizen,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: deletedAt ?? this.deletedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (rawMaterialId.present) {
      map['raw_material_id'] = Variable<String>(rawMaterialId.value);
    }
    if (chargennummer.present) {
      map['chargennummer'] = Variable<String>(chargennummer.value);
    }
    if (mhd.present) {
      map['mhd'] = Variable<DateTime>(mhd.value);
    }
    if (eingangsDatum.present) {
      map['eingangs_datum'] = Variable<DateTime>(eingangsDatum.value);
    }
    if (mengeInitial.present) {
      map['menge_initial'] = Variable<double>(mengeInitial.value);
    }
    if (mengeAktuell.present) {
      map['menge_aktuell'] = Variable<double>(mengeAktuell.value);
    }
    if (einheit.present) {
      map['einheit'] = Variable<String>(einheit.value);
    }
    if (lieferant.present) {
      map['lieferant'] = Variable<String>(lieferant.value);
    }
    if (notizen.present) {
      map['notizen'] = Variable<String>(notizen.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (deletedAt.present) {
      map['deleted_at'] = Variable<DateTime>(deletedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('RawMaterialBatchesCompanion(')
          ..write('id: $id, ')
          ..write('rawMaterialId: $rawMaterialId, ')
          ..write('chargennummer: $chargennummer, ')
          ..write('mhd: $mhd, ')
          ..write('eingangsDatum: $eingangsDatum, ')
          ..write('mengeInitial: $mengeInitial, ')
          ..write('mengeAktuell: $mengeAktuell, ')
          ..write('einheit: $einheit, ')
          ..write('lieferant: $lieferant, ')
          ..write('notizen: $notizen, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ProductionTasksTable extends ProductionTasks
    with TableInfo<$ProductionTasksTable, ProductionTask> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ProductionTasksTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
      'id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _productIdMeta =
      const VerificationMeta('productId');
  @override
  late final GeneratedColumn<String> productId = GeneratedColumn<String>(
      'product_id', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: true,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('REFERENCES products (id)'));
  static const VerificationMeta _mengeKgMeta =
      const VerificationMeta('mengeKg');
  @override
  late final GeneratedColumn<double> mengeKg = GeneratedColumn<double>(
      'menge_kg', aliasedName, false,
      type: DriftSqlType.double, requiredDuringInsert: true);
  static const VerificationMeta _datumMeta = const VerificationMeta('datum');
  @override
  late final GeneratedColumn<DateTime> datum = GeneratedColumn<DateTime>(
      'datum', aliasedName, false,
      type: DriftSqlType.dateTime, requiredDuringInsert: true);
  static const VerificationMeta _abteilungMeta =
      const VerificationMeta('abteilung');
  @override
  late final GeneratedColumn<String> abteilung = GeneratedColumn<String>(
      'abteilung', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _startZeitMeta =
      const VerificationMeta('startZeit');
  @override
  late final GeneratedColumn<String> startZeit = GeneratedColumn<String>(
      'start_zeit', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _geplanteDauerMinutenMeta =
      const VerificationMeta('geplanteDauerMinuten');
  @override
  late final GeneratedColumn<double> geplanteDauerMinuten =
      GeneratedColumn<double>('geplante_dauer_minuten', aliasedName, false,
          type: DriftSqlType.double, requiredDuringInsert: true);
  static const VerificationMeta _geplanteMitarbeiterMeta =
      const VerificationMeta('geplanteMitarbeiter');
  @override
  late final GeneratedColumn<int> geplanteMitarbeiter = GeneratedColumn<int>(
      'geplante_mitarbeiter', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _statusMeta = const VerificationMeta('status');
  @override
  late final GeneratedColumn<String> status = GeneratedColumn<String>(
      'status', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const Constant('geplant'));
  static const VerificationMeta _parentTaskIdMeta =
      const VerificationMeta('parentTaskId');
  @override
  late final GeneratedColumn<String> parentTaskId = GeneratedColumn<String>(
      'parent_task_id', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _notizenMeta =
      const VerificationMeta('notizen');
  @override
  late final GeneratedColumn<String> notizen = GeneratedColumn<String>(
      'notizen', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _createdAtMeta =
      const VerificationMeta('createdAt');
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
      'created_at', aliasedName, false,
      type: DriftSqlType.dateTime,
      requiredDuringInsert: false,
      defaultValue: currentDateAndTime);
  static const VerificationMeta _updatedAtMeta =
      const VerificationMeta('updatedAt');
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
      'updated_at', aliasedName, false,
      type: DriftSqlType.dateTime,
      requiredDuringInsert: false,
      defaultValue: currentDateAndTime);
  static const VerificationMeta _deletedAtMeta =
      const VerificationMeta('deletedAt');
  @override
  late final GeneratedColumn<DateTime> deletedAt = GeneratedColumn<DateTime>(
      'deleted_at', aliasedName, true,
      type: DriftSqlType.dateTime, requiredDuringInsert: false);
  @override
  List<GeneratedColumn> get $columns => [
        id,
        productId,
        mengeKg,
        datum,
        abteilung,
        startZeit,
        geplanteDauerMinuten,
        geplanteMitarbeiter,
        status,
        parentTaskId,
        notizen,
        createdAt,
        updatedAt,
        deletedAt
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'production_tasks';
  @override
  VerificationContext validateIntegrity(Insertable<ProductionTask> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('product_id')) {
      context.handle(_productIdMeta,
          productId.isAcceptableOrUnknown(data['product_id']!, _productIdMeta));
    } else if (isInserting) {
      context.missing(_productIdMeta);
    }
    if (data.containsKey('menge_kg')) {
      context.handle(_mengeKgMeta,
          mengeKg.isAcceptableOrUnknown(data['menge_kg']!, _mengeKgMeta));
    } else if (isInserting) {
      context.missing(_mengeKgMeta);
    }
    if (data.containsKey('datum')) {
      context.handle(
          _datumMeta, datum.isAcceptableOrUnknown(data['datum']!, _datumMeta));
    } else if (isInserting) {
      context.missing(_datumMeta);
    }
    if (data.containsKey('abteilung')) {
      context.handle(_abteilungMeta,
          abteilung.isAcceptableOrUnknown(data['abteilung']!, _abteilungMeta));
    } else if (isInserting) {
      context.missing(_abteilungMeta);
    }
    if (data.containsKey('start_zeit')) {
      context.handle(_startZeitMeta,
          startZeit.isAcceptableOrUnknown(data['start_zeit']!, _startZeitMeta));
    }
    if (data.containsKey('geplante_dauer_minuten')) {
      context.handle(
          _geplanteDauerMinutenMeta,
          geplanteDauerMinuten.isAcceptableOrUnknown(
              data['geplante_dauer_minuten']!, _geplanteDauerMinutenMeta));
    } else if (isInserting) {
      context.missing(_geplanteDauerMinutenMeta);
    }
    if (data.containsKey('geplante_mitarbeiter')) {
      context.handle(
          _geplanteMitarbeiterMeta,
          geplanteMitarbeiter.isAcceptableOrUnknown(
              data['geplante_mitarbeiter']!, _geplanteMitarbeiterMeta));
    } else if (isInserting) {
      context.missing(_geplanteMitarbeiterMeta);
    }
    if (data.containsKey('status')) {
      context.handle(_statusMeta,
          status.isAcceptableOrUnknown(data['status']!, _statusMeta));
    }
    if (data.containsKey('parent_task_id')) {
      context.handle(
          _parentTaskIdMeta,
          parentTaskId.isAcceptableOrUnknown(
              data['parent_task_id']!, _parentTaskIdMeta));
    }
    if (data.containsKey('notizen')) {
      context.handle(_notizenMeta,
          notizen.isAcceptableOrUnknown(data['notizen']!, _notizenMeta));
    }
    if (data.containsKey('created_at')) {
      context.handle(_createdAtMeta,
          createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta));
    }
    if (data.containsKey('updated_at')) {
      context.handle(_updatedAtMeta,
          updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta));
    }
    if (data.containsKey('deleted_at')) {
      context.handle(_deletedAtMeta,
          deletedAt.isAcceptableOrUnknown(data['deleted_at']!, _deletedAtMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  ProductionTask map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ProductionTask(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}id'])!,
      productId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}product_id'])!,
      mengeKg: attachedDatabase.typeMapping
          .read(DriftSqlType.double, data['${effectivePrefix}menge_kg'])!,
      datum: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}datum'])!,
      abteilung: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}abteilung'])!,
      startZeit: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}start_zeit']),
      geplanteDauerMinuten: attachedDatabase.typeMapping.read(
          DriftSqlType.double,
          data['${effectivePrefix}geplante_dauer_minuten'])!,
      geplanteMitarbeiter: attachedDatabase.typeMapping.read(
          DriftSqlType.int, data['${effectivePrefix}geplante_mitarbeiter'])!,
      status: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}status'])!,
      parentTaskId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}parent_task_id']),
      notizen: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}notizen']),
      createdAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}created_at'])!,
      updatedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}updated_at'])!,
      deletedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}deleted_at']),
    );
  }

  @override
  $ProductionTasksTable createAlias(String alias) {
    return $ProductionTasksTable(attachedDatabase, alias);
  }
}

class ProductionTask extends DataClass implements Insertable<ProductionTask> {
  final String id;
  final String productId;
  final double mengeKg;

  /// Das Datum, für das der Auftrag geplant ist (Konvention: 00:00 Uhr lokal).
  final DateTime datum;

  /// Abteilung, in der dieser Task ausgeführt wird.
  /// Gespeichert als [Abteilung.dbValue].
  final String abteilung;

  /// Geplante Startzeit als "HH:MM"-String (z.B. "08:30"). Null, wenn der
  /// Task für den Tag geplant ist, aber keine feste Uhrzeit hat.
  final String? startZeit;

  /// Aus Skalierung berechnete Dauer, aber speicherbar, weil manuell
  /// übersteuerbar.
  final double geplanteDauerMinuten;
  final int geplanteMitarbeiter;

  /// Status des Auftrags. Erlaubte Werte (als Konstanten im Repo-Layer):
  /// 'geplant', 'in_arbeit', 'fertig', 'storniert'.
  final String status;

  /// Self-Referenz für automatisch erzeugte Vor-Tasks.
  /// Beispiel: Auftrag "Leberkäse Bratstraße" erzeugt vorgelagert
  /// "Leberkäse Wurstküche" und "Leberkäse Zerlegung" — alle mit
  /// parent_task_id auf den Bratstraßen-Task.
  final String? parentTaskId;
  final String? notizen;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;
  const ProductionTask(
      {required this.id,
      required this.productId,
      required this.mengeKg,
      required this.datum,
      required this.abteilung,
      this.startZeit,
      required this.geplanteDauerMinuten,
      required this.geplanteMitarbeiter,
      required this.status,
      this.parentTaskId,
      this.notizen,
      required this.createdAt,
      required this.updatedAt,
      this.deletedAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['product_id'] = Variable<String>(productId);
    map['menge_kg'] = Variable<double>(mengeKg);
    map['datum'] = Variable<DateTime>(datum);
    map['abteilung'] = Variable<String>(abteilung);
    if (!nullToAbsent || startZeit != null) {
      map['start_zeit'] = Variable<String>(startZeit);
    }
    map['geplante_dauer_minuten'] = Variable<double>(geplanteDauerMinuten);
    map['geplante_mitarbeiter'] = Variable<int>(geplanteMitarbeiter);
    map['status'] = Variable<String>(status);
    if (!nullToAbsent || parentTaskId != null) {
      map['parent_task_id'] = Variable<String>(parentTaskId);
    }
    if (!nullToAbsent || notizen != null) {
      map['notizen'] = Variable<String>(notizen);
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    if (!nullToAbsent || deletedAt != null) {
      map['deleted_at'] = Variable<DateTime>(deletedAt);
    }
    return map;
  }

  ProductionTasksCompanion toCompanion(bool nullToAbsent) {
    return ProductionTasksCompanion(
      id: Value(id),
      productId: Value(productId),
      mengeKg: Value(mengeKg),
      datum: Value(datum),
      abteilung: Value(abteilung),
      startZeit: startZeit == null && nullToAbsent
          ? const Value.absent()
          : Value(startZeit),
      geplanteDauerMinuten: Value(geplanteDauerMinuten),
      geplanteMitarbeiter: Value(geplanteMitarbeiter),
      status: Value(status),
      parentTaskId: parentTaskId == null && nullToAbsent
          ? const Value.absent()
          : Value(parentTaskId),
      notizen: notizen == null && nullToAbsent
          ? const Value.absent()
          : Value(notizen),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
      deletedAt: deletedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(deletedAt),
    );
  }

  factory ProductionTask.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ProductionTask(
      id: serializer.fromJson<String>(json['id']),
      productId: serializer.fromJson<String>(json['productId']),
      mengeKg: serializer.fromJson<double>(json['mengeKg']),
      datum: serializer.fromJson<DateTime>(json['datum']),
      abteilung: serializer.fromJson<String>(json['abteilung']),
      startZeit: serializer.fromJson<String?>(json['startZeit']),
      geplanteDauerMinuten:
          serializer.fromJson<double>(json['geplanteDauerMinuten']),
      geplanteMitarbeiter:
          serializer.fromJson<int>(json['geplanteMitarbeiter']),
      status: serializer.fromJson<String>(json['status']),
      parentTaskId: serializer.fromJson<String?>(json['parentTaskId']),
      notizen: serializer.fromJson<String?>(json['notizen']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
      deletedAt: serializer.fromJson<DateTime?>(json['deletedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'productId': serializer.toJson<String>(productId),
      'mengeKg': serializer.toJson<double>(mengeKg),
      'datum': serializer.toJson<DateTime>(datum),
      'abteilung': serializer.toJson<String>(abteilung),
      'startZeit': serializer.toJson<String?>(startZeit),
      'geplanteDauerMinuten': serializer.toJson<double>(geplanteDauerMinuten),
      'geplanteMitarbeiter': serializer.toJson<int>(geplanteMitarbeiter),
      'status': serializer.toJson<String>(status),
      'parentTaskId': serializer.toJson<String?>(parentTaskId),
      'notizen': serializer.toJson<String?>(notizen),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
      'deletedAt': serializer.toJson<DateTime?>(deletedAt),
    };
  }

  ProductionTask copyWith(
          {String? id,
          String? productId,
          double? mengeKg,
          DateTime? datum,
          String? abteilung,
          Value<String?> startZeit = const Value.absent(),
          double? geplanteDauerMinuten,
          int? geplanteMitarbeiter,
          String? status,
          Value<String?> parentTaskId = const Value.absent(),
          Value<String?> notizen = const Value.absent(),
          DateTime? createdAt,
          DateTime? updatedAt,
          Value<DateTime?> deletedAt = const Value.absent()}) =>
      ProductionTask(
        id: id ?? this.id,
        productId: productId ?? this.productId,
        mengeKg: mengeKg ?? this.mengeKg,
        datum: datum ?? this.datum,
        abteilung: abteilung ?? this.abteilung,
        startZeit: startZeit.present ? startZeit.value : this.startZeit,
        geplanteDauerMinuten: geplanteDauerMinuten ?? this.geplanteDauerMinuten,
        geplanteMitarbeiter: geplanteMitarbeiter ?? this.geplanteMitarbeiter,
        status: status ?? this.status,
        parentTaskId:
            parentTaskId.present ? parentTaskId.value : this.parentTaskId,
        notizen: notizen.present ? notizen.value : this.notizen,
        createdAt: createdAt ?? this.createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
        deletedAt: deletedAt.present ? deletedAt.value : this.deletedAt,
      );
  ProductionTask copyWithCompanion(ProductionTasksCompanion data) {
    return ProductionTask(
      id: data.id.present ? data.id.value : this.id,
      productId: data.productId.present ? data.productId.value : this.productId,
      mengeKg: data.mengeKg.present ? data.mengeKg.value : this.mengeKg,
      datum: data.datum.present ? data.datum.value : this.datum,
      abteilung: data.abteilung.present ? data.abteilung.value : this.abteilung,
      startZeit: data.startZeit.present ? data.startZeit.value : this.startZeit,
      geplanteDauerMinuten: data.geplanteDauerMinuten.present
          ? data.geplanteDauerMinuten.value
          : this.geplanteDauerMinuten,
      geplanteMitarbeiter: data.geplanteMitarbeiter.present
          ? data.geplanteMitarbeiter.value
          : this.geplanteMitarbeiter,
      status: data.status.present ? data.status.value : this.status,
      parentTaskId: data.parentTaskId.present
          ? data.parentTaskId.value
          : this.parentTaskId,
      notizen: data.notizen.present ? data.notizen.value : this.notizen,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      deletedAt: data.deletedAt.present ? data.deletedAt.value : this.deletedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ProductionTask(')
          ..write('id: $id, ')
          ..write('productId: $productId, ')
          ..write('mengeKg: $mengeKg, ')
          ..write('datum: $datum, ')
          ..write('abteilung: $abteilung, ')
          ..write('startZeit: $startZeit, ')
          ..write('geplanteDauerMinuten: $geplanteDauerMinuten, ')
          ..write('geplanteMitarbeiter: $geplanteMitarbeiter, ')
          ..write('status: $status, ')
          ..write('parentTaskId: $parentTaskId, ')
          ..write('notizen: $notizen, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
      id,
      productId,
      mengeKg,
      datum,
      abteilung,
      startZeit,
      geplanteDauerMinuten,
      geplanteMitarbeiter,
      status,
      parentTaskId,
      notizen,
      createdAt,
      updatedAt,
      deletedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ProductionTask &&
          other.id == this.id &&
          other.productId == this.productId &&
          other.mengeKg == this.mengeKg &&
          other.datum == this.datum &&
          other.abteilung == this.abteilung &&
          other.startZeit == this.startZeit &&
          other.geplanteDauerMinuten == this.geplanteDauerMinuten &&
          other.geplanteMitarbeiter == this.geplanteMitarbeiter &&
          other.status == this.status &&
          other.parentTaskId == this.parentTaskId &&
          other.notizen == this.notizen &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt &&
          other.deletedAt == this.deletedAt);
}

class ProductionTasksCompanion extends UpdateCompanion<ProductionTask> {
  final Value<String> id;
  final Value<String> productId;
  final Value<double> mengeKg;
  final Value<DateTime> datum;
  final Value<String> abteilung;
  final Value<String?> startZeit;
  final Value<double> geplanteDauerMinuten;
  final Value<int> geplanteMitarbeiter;
  final Value<String> status;
  final Value<String?> parentTaskId;
  final Value<String?> notizen;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<DateTime?> deletedAt;
  final Value<int> rowid;
  const ProductionTasksCompanion({
    this.id = const Value.absent(),
    this.productId = const Value.absent(),
    this.mengeKg = const Value.absent(),
    this.datum = const Value.absent(),
    this.abteilung = const Value.absent(),
    this.startZeit = const Value.absent(),
    this.geplanteDauerMinuten = const Value.absent(),
    this.geplanteMitarbeiter = const Value.absent(),
    this.status = const Value.absent(),
    this.parentTaskId = const Value.absent(),
    this.notizen = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ProductionTasksCompanion.insert({
    required String id,
    required String productId,
    required double mengeKg,
    required DateTime datum,
    required String abteilung,
    this.startZeit = const Value.absent(),
    required double geplanteDauerMinuten,
    required int geplanteMitarbeiter,
    this.status = const Value.absent(),
    this.parentTaskId = const Value.absent(),
    this.notizen = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  })  : id = Value(id),
        productId = Value(productId),
        mengeKg = Value(mengeKg),
        datum = Value(datum),
        abteilung = Value(abteilung),
        geplanteDauerMinuten = Value(geplanteDauerMinuten),
        geplanteMitarbeiter = Value(geplanteMitarbeiter);
  static Insertable<ProductionTask> custom({
    Expression<String>? id,
    Expression<String>? productId,
    Expression<double>? mengeKg,
    Expression<DateTime>? datum,
    Expression<String>? abteilung,
    Expression<String>? startZeit,
    Expression<double>? geplanteDauerMinuten,
    Expression<int>? geplanteMitarbeiter,
    Expression<String>? status,
    Expression<String>? parentTaskId,
    Expression<String>? notizen,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<DateTime>? deletedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (productId != null) 'product_id': productId,
      if (mengeKg != null) 'menge_kg': mengeKg,
      if (datum != null) 'datum': datum,
      if (abteilung != null) 'abteilung': abteilung,
      if (startZeit != null) 'start_zeit': startZeit,
      if (geplanteDauerMinuten != null)
        'geplante_dauer_minuten': geplanteDauerMinuten,
      if (geplanteMitarbeiter != null)
        'geplante_mitarbeiter': geplanteMitarbeiter,
      if (status != null) 'status': status,
      if (parentTaskId != null) 'parent_task_id': parentTaskId,
      if (notizen != null) 'notizen': notizen,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (deletedAt != null) 'deleted_at': deletedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ProductionTasksCompanion copyWith(
      {Value<String>? id,
      Value<String>? productId,
      Value<double>? mengeKg,
      Value<DateTime>? datum,
      Value<String>? abteilung,
      Value<String?>? startZeit,
      Value<double>? geplanteDauerMinuten,
      Value<int>? geplanteMitarbeiter,
      Value<String>? status,
      Value<String?>? parentTaskId,
      Value<String?>? notizen,
      Value<DateTime>? createdAt,
      Value<DateTime>? updatedAt,
      Value<DateTime?>? deletedAt,
      Value<int>? rowid}) {
    return ProductionTasksCompanion(
      id: id ?? this.id,
      productId: productId ?? this.productId,
      mengeKg: mengeKg ?? this.mengeKg,
      datum: datum ?? this.datum,
      abteilung: abteilung ?? this.abteilung,
      startZeit: startZeit ?? this.startZeit,
      geplanteDauerMinuten: geplanteDauerMinuten ?? this.geplanteDauerMinuten,
      geplanteMitarbeiter: geplanteMitarbeiter ?? this.geplanteMitarbeiter,
      status: status ?? this.status,
      parentTaskId: parentTaskId ?? this.parentTaskId,
      notizen: notizen ?? this.notizen,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: deletedAt ?? this.deletedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (productId.present) {
      map['product_id'] = Variable<String>(productId.value);
    }
    if (mengeKg.present) {
      map['menge_kg'] = Variable<double>(mengeKg.value);
    }
    if (datum.present) {
      map['datum'] = Variable<DateTime>(datum.value);
    }
    if (abteilung.present) {
      map['abteilung'] = Variable<String>(abteilung.value);
    }
    if (startZeit.present) {
      map['start_zeit'] = Variable<String>(startZeit.value);
    }
    if (geplanteDauerMinuten.present) {
      map['geplante_dauer_minuten'] =
          Variable<double>(geplanteDauerMinuten.value);
    }
    if (geplanteMitarbeiter.present) {
      map['geplante_mitarbeiter'] = Variable<int>(geplanteMitarbeiter.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(status.value);
    }
    if (parentTaskId.present) {
      map['parent_task_id'] = Variable<String>(parentTaskId.value);
    }
    if (notizen.present) {
      map['notizen'] = Variable<String>(notizen.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (deletedAt.present) {
      map['deleted_at'] = Variable<DateTime>(deletedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ProductionTasksCompanion(')
          ..write('id: $id, ')
          ..write('productId: $productId, ')
          ..write('mengeKg: $mengeKg, ')
          ..write('datum: $datum, ')
          ..write('abteilung: $abteilung, ')
          ..write('startZeit: $startZeit, ')
          ..write('geplanteDauerMinuten: $geplanteDauerMinuten, ')
          ..write('geplanteMitarbeiter: $geplanteMitarbeiter, ')
          ..write('status: $status, ')
          ..write('parentTaskId: $parentTaskId, ')
          ..write('notizen: $notizen, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ProductionRunsTable extends ProductionRuns
    with TableInfo<$ProductionRunsTable, ProductionRun> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ProductionRunsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
      'id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _taskIdMeta = const VerificationMeta('taskId');
  @override
  late final GeneratedColumn<String> taskId = GeneratedColumn<String>(
      'task_id', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: true,
      defaultConstraints: GeneratedColumn.constraintIsAlways(
          'REFERENCES production_tasks (id)'));
  static const VerificationMeta _tatsaechlicheDauerMinutenMeta =
      const VerificationMeta('tatsaechlicheDauerMinuten');
  @override
  late final GeneratedColumn<double> tatsaechlicheDauerMinuten =
      GeneratedColumn<double>('tatsaechliche_dauer_minuten', aliasedName, false,
          type: DriftSqlType.double, requiredDuringInsert: true);
  static const VerificationMeta _tatsaechlicheMitarbeiterMeta =
      const VerificationMeta('tatsaechlicheMitarbeiter');
  @override
  late final GeneratedColumn<int> tatsaechlicheMitarbeiter =
      GeneratedColumn<int>('tatsaechliche_mitarbeiter', aliasedName, false,
          type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _tatsaechlicheMengeKgMeta =
      const VerificationMeta('tatsaechlicheMengeKg');
  @override
  late final GeneratedColumn<double> tatsaechlicheMengeKg =
      GeneratedColumn<double>('tatsaechliche_menge_kg', aliasedName, false,
          type: DriftSqlType.double, requiredDuringInsert: true);
  static const VerificationMeta _verwendeteChargenJsonMeta =
      const VerificationMeta('verwendeteChargenJson');
  @override
  late final GeneratedColumn<String> verwendeteChargenJson =
      GeneratedColumn<String>('verwendete_chargen_json', aliasedName, true,
          type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _notizenMeta =
      const VerificationMeta('notizen');
  @override
  late final GeneratedColumn<String> notizen = GeneratedColumn<String>(
      'notizen', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _erfasstVonMeta =
      const VerificationMeta('erfasstVon');
  @override
  late final GeneratedColumn<String> erfasstVon = GeneratedColumn<String>(
      'erfasst_von', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _erfasstAmMeta =
      const VerificationMeta('erfasstAm');
  @override
  late final GeneratedColumn<DateTime> erfasstAm = GeneratedColumn<DateTime>(
      'erfasst_am', aliasedName, false,
      type: DriftSqlType.dateTime,
      requiredDuringInsert: false,
      defaultValue: currentDateAndTime);
  static const VerificationMeta _createdAtMeta =
      const VerificationMeta('createdAt');
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
      'created_at', aliasedName, false,
      type: DriftSqlType.dateTime,
      requiredDuringInsert: false,
      defaultValue: currentDateAndTime);
  static const VerificationMeta _updatedAtMeta =
      const VerificationMeta('updatedAt');
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
      'updated_at', aliasedName, false,
      type: DriftSqlType.dateTime,
      requiredDuringInsert: false,
      defaultValue: currentDateAndTime);
  static const VerificationMeta _deletedAtMeta =
      const VerificationMeta('deletedAt');
  @override
  late final GeneratedColumn<DateTime> deletedAt = GeneratedColumn<DateTime>(
      'deleted_at', aliasedName, true,
      type: DriftSqlType.dateTime, requiredDuringInsert: false);
  @override
  List<GeneratedColumn> get $columns => [
        id,
        taskId,
        tatsaechlicheDauerMinuten,
        tatsaechlicheMitarbeiter,
        tatsaechlicheMengeKg,
        verwendeteChargenJson,
        notizen,
        erfasstVon,
        erfasstAm,
        createdAt,
        updatedAt,
        deletedAt
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'production_runs';
  @override
  VerificationContext validateIntegrity(Insertable<ProductionRun> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('task_id')) {
      context.handle(_taskIdMeta,
          taskId.isAcceptableOrUnknown(data['task_id']!, _taskIdMeta));
    } else if (isInserting) {
      context.missing(_taskIdMeta);
    }
    if (data.containsKey('tatsaechliche_dauer_minuten')) {
      context.handle(
          _tatsaechlicheDauerMinutenMeta,
          tatsaechlicheDauerMinuten.isAcceptableOrUnknown(
              data['tatsaechliche_dauer_minuten']!,
              _tatsaechlicheDauerMinutenMeta));
    } else if (isInserting) {
      context.missing(_tatsaechlicheDauerMinutenMeta);
    }
    if (data.containsKey('tatsaechliche_mitarbeiter')) {
      context.handle(
          _tatsaechlicheMitarbeiterMeta,
          tatsaechlicheMitarbeiter.isAcceptableOrUnknown(
              data['tatsaechliche_mitarbeiter']!,
              _tatsaechlicheMitarbeiterMeta));
    } else if (isInserting) {
      context.missing(_tatsaechlicheMitarbeiterMeta);
    }
    if (data.containsKey('tatsaechliche_menge_kg')) {
      context.handle(
          _tatsaechlicheMengeKgMeta,
          tatsaechlicheMengeKg.isAcceptableOrUnknown(
              data['tatsaechliche_menge_kg']!, _tatsaechlicheMengeKgMeta));
    } else if (isInserting) {
      context.missing(_tatsaechlicheMengeKgMeta);
    }
    if (data.containsKey('verwendete_chargen_json')) {
      context.handle(
          _verwendeteChargenJsonMeta,
          verwendeteChargenJson.isAcceptableOrUnknown(
              data['verwendete_chargen_json']!, _verwendeteChargenJsonMeta));
    }
    if (data.containsKey('notizen')) {
      context.handle(_notizenMeta,
          notizen.isAcceptableOrUnknown(data['notizen']!, _notizenMeta));
    }
    if (data.containsKey('erfasst_von')) {
      context.handle(
          _erfasstVonMeta,
          erfasstVon.isAcceptableOrUnknown(
              data['erfasst_von']!, _erfasstVonMeta));
    }
    if (data.containsKey('erfasst_am')) {
      context.handle(_erfasstAmMeta,
          erfasstAm.isAcceptableOrUnknown(data['erfasst_am']!, _erfasstAmMeta));
    }
    if (data.containsKey('created_at')) {
      context.handle(_createdAtMeta,
          createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta));
    }
    if (data.containsKey('updated_at')) {
      context.handle(_updatedAtMeta,
          updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta));
    }
    if (data.containsKey('deleted_at')) {
      context.handle(_deletedAtMeta,
          deletedAt.isAcceptableOrUnknown(data['deleted_at']!, _deletedAtMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  ProductionRun map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ProductionRun(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}id'])!,
      taskId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}task_id'])!,
      tatsaechlicheDauerMinuten: attachedDatabase.typeMapping.read(
          DriftSqlType.double,
          data['${effectivePrefix}tatsaechliche_dauer_minuten'])!,
      tatsaechlicheMitarbeiter: attachedDatabase.typeMapping.read(
          DriftSqlType.int,
          data['${effectivePrefix}tatsaechliche_mitarbeiter'])!,
      tatsaechlicheMengeKg: attachedDatabase.typeMapping.read(
          DriftSqlType.double,
          data['${effectivePrefix}tatsaechliche_menge_kg'])!,
      verwendeteChargenJson: attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}verwendete_chargen_json']),
      notizen: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}notizen']),
      erfasstVon: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}erfasst_von']),
      erfasstAm: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}erfasst_am'])!,
      createdAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}created_at'])!,
      updatedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}updated_at'])!,
      deletedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}deleted_at']),
    );
  }

  @override
  $ProductionRunsTable createAlias(String alias) {
    return $ProductionRunsTable(attachedDatabase, alias);
  }
}

class ProductionRun extends DataClass implements Insertable<ProductionRun> {
  final String id;
  final String taskId;

  /// Tatsächlich verbrauchte Zeit am Stück, in Minuten.
  final double tatsaechlicheDauerMinuten;
  final int tatsaechlicheMitarbeiter;

  /// Tatsächlich produzierte Menge — kann von der geplanten abweichen
  /// (weniger Rohware da, Maschinenausfall, mehr bestellt etc.).
  final double tatsaechlicheMengeKg;

  /// JSON-Objekt: welche Chargen wurden verbraucht und wieviel.
  /// Format: `{"batch_uuid_1": 45.2, "batch_uuid_2": 10.0}`
  /// Wird in der MRP-/Chargen-Logik gegen [RawMaterialBatches.mengeAktuell]
  /// verrechnet. HACCP-relevant: komplette Rückverfolgbarkeit.
  final String? verwendeteChargenJson;
  final String? notizen;

  /// Wer hat die Werte eingetragen (Freitext, in Phase 1 noch kein User-System).
  final String? erfasstVon;
  final DateTime erfasstAm;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;
  const ProductionRun(
      {required this.id,
      required this.taskId,
      required this.tatsaechlicheDauerMinuten,
      required this.tatsaechlicheMitarbeiter,
      required this.tatsaechlicheMengeKg,
      this.verwendeteChargenJson,
      this.notizen,
      this.erfasstVon,
      required this.erfasstAm,
      required this.createdAt,
      required this.updatedAt,
      this.deletedAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['task_id'] = Variable<String>(taskId);
    map['tatsaechliche_dauer_minuten'] =
        Variable<double>(tatsaechlicheDauerMinuten);
    map['tatsaechliche_mitarbeiter'] = Variable<int>(tatsaechlicheMitarbeiter);
    map['tatsaechliche_menge_kg'] = Variable<double>(tatsaechlicheMengeKg);
    if (!nullToAbsent || verwendeteChargenJson != null) {
      map['verwendete_chargen_json'] = Variable<String>(verwendeteChargenJson);
    }
    if (!nullToAbsent || notizen != null) {
      map['notizen'] = Variable<String>(notizen);
    }
    if (!nullToAbsent || erfasstVon != null) {
      map['erfasst_von'] = Variable<String>(erfasstVon);
    }
    map['erfasst_am'] = Variable<DateTime>(erfasstAm);
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    if (!nullToAbsent || deletedAt != null) {
      map['deleted_at'] = Variable<DateTime>(deletedAt);
    }
    return map;
  }

  ProductionRunsCompanion toCompanion(bool nullToAbsent) {
    return ProductionRunsCompanion(
      id: Value(id),
      taskId: Value(taskId),
      tatsaechlicheDauerMinuten: Value(tatsaechlicheDauerMinuten),
      tatsaechlicheMitarbeiter: Value(tatsaechlicheMitarbeiter),
      tatsaechlicheMengeKg: Value(tatsaechlicheMengeKg),
      verwendeteChargenJson: verwendeteChargenJson == null && nullToAbsent
          ? const Value.absent()
          : Value(verwendeteChargenJson),
      notizen: notizen == null && nullToAbsent
          ? const Value.absent()
          : Value(notizen),
      erfasstVon: erfasstVon == null && nullToAbsent
          ? const Value.absent()
          : Value(erfasstVon),
      erfasstAm: Value(erfasstAm),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
      deletedAt: deletedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(deletedAt),
    );
  }

  factory ProductionRun.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ProductionRun(
      id: serializer.fromJson<String>(json['id']),
      taskId: serializer.fromJson<String>(json['taskId']),
      tatsaechlicheDauerMinuten:
          serializer.fromJson<double>(json['tatsaechlicheDauerMinuten']),
      tatsaechlicheMitarbeiter:
          serializer.fromJson<int>(json['tatsaechlicheMitarbeiter']),
      tatsaechlicheMengeKg:
          serializer.fromJson<double>(json['tatsaechlicheMengeKg']),
      verwendeteChargenJson:
          serializer.fromJson<String?>(json['verwendeteChargenJson']),
      notizen: serializer.fromJson<String?>(json['notizen']),
      erfasstVon: serializer.fromJson<String?>(json['erfasstVon']),
      erfasstAm: serializer.fromJson<DateTime>(json['erfasstAm']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
      deletedAt: serializer.fromJson<DateTime?>(json['deletedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'taskId': serializer.toJson<String>(taskId),
      'tatsaechlicheDauerMinuten':
          serializer.toJson<double>(tatsaechlicheDauerMinuten),
      'tatsaechlicheMitarbeiter':
          serializer.toJson<int>(tatsaechlicheMitarbeiter),
      'tatsaechlicheMengeKg': serializer.toJson<double>(tatsaechlicheMengeKg),
      'verwendeteChargenJson':
          serializer.toJson<String?>(verwendeteChargenJson),
      'notizen': serializer.toJson<String?>(notizen),
      'erfasstVon': serializer.toJson<String?>(erfasstVon),
      'erfasstAm': serializer.toJson<DateTime>(erfasstAm),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
      'deletedAt': serializer.toJson<DateTime?>(deletedAt),
    };
  }

  ProductionRun copyWith(
          {String? id,
          String? taskId,
          double? tatsaechlicheDauerMinuten,
          int? tatsaechlicheMitarbeiter,
          double? tatsaechlicheMengeKg,
          Value<String?> verwendeteChargenJson = const Value.absent(),
          Value<String?> notizen = const Value.absent(),
          Value<String?> erfasstVon = const Value.absent(),
          DateTime? erfasstAm,
          DateTime? createdAt,
          DateTime? updatedAt,
          Value<DateTime?> deletedAt = const Value.absent()}) =>
      ProductionRun(
        id: id ?? this.id,
        taskId: taskId ?? this.taskId,
        tatsaechlicheDauerMinuten:
            tatsaechlicheDauerMinuten ?? this.tatsaechlicheDauerMinuten,
        tatsaechlicheMitarbeiter:
            tatsaechlicheMitarbeiter ?? this.tatsaechlicheMitarbeiter,
        tatsaechlicheMengeKg: tatsaechlicheMengeKg ?? this.tatsaechlicheMengeKg,
        verwendeteChargenJson: verwendeteChargenJson.present
            ? verwendeteChargenJson.value
            : this.verwendeteChargenJson,
        notizen: notizen.present ? notizen.value : this.notizen,
        erfasstVon: erfasstVon.present ? erfasstVon.value : this.erfasstVon,
        erfasstAm: erfasstAm ?? this.erfasstAm,
        createdAt: createdAt ?? this.createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
        deletedAt: deletedAt.present ? deletedAt.value : this.deletedAt,
      );
  ProductionRun copyWithCompanion(ProductionRunsCompanion data) {
    return ProductionRun(
      id: data.id.present ? data.id.value : this.id,
      taskId: data.taskId.present ? data.taskId.value : this.taskId,
      tatsaechlicheDauerMinuten: data.tatsaechlicheDauerMinuten.present
          ? data.tatsaechlicheDauerMinuten.value
          : this.tatsaechlicheDauerMinuten,
      tatsaechlicheMitarbeiter: data.tatsaechlicheMitarbeiter.present
          ? data.tatsaechlicheMitarbeiter.value
          : this.tatsaechlicheMitarbeiter,
      tatsaechlicheMengeKg: data.tatsaechlicheMengeKg.present
          ? data.tatsaechlicheMengeKg.value
          : this.tatsaechlicheMengeKg,
      verwendeteChargenJson: data.verwendeteChargenJson.present
          ? data.verwendeteChargenJson.value
          : this.verwendeteChargenJson,
      notizen: data.notizen.present ? data.notizen.value : this.notizen,
      erfasstVon:
          data.erfasstVon.present ? data.erfasstVon.value : this.erfasstVon,
      erfasstAm: data.erfasstAm.present ? data.erfasstAm.value : this.erfasstAm,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      deletedAt: data.deletedAt.present ? data.deletedAt.value : this.deletedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ProductionRun(')
          ..write('id: $id, ')
          ..write('taskId: $taskId, ')
          ..write('tatsaechlicheDauerMinuten: $tatsaechlicheDauerMinuten, ')
          ..write('tatsaechlicheMitarbeiter: $tatsaechlicheMitarbeiter, ')
          ..write('tatsaechlicheMengeKg: $tatsaechlicheMengeKg, ')
          ..write('verwendeteChargenJson: $verwendeteChargenJson, ')
          ..write('notizen: $notizen, ')
          ..write('erfasstVon: $erfasstVon, ')
          ..write('erfasstAm: $erfasstAm, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
      id,
      taskId,
      tatsaechlicheDauerMinuten,
      tatsaechlicheMitarbeiter,
      tatsaechlicheMengeKg,
      verwendeteChargenJson,
      notizen,
      erfasstVon,
      erfasstAm,
      createdAt,
      updatedAt,
      deletedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ProductionRun &&
          other.id == this.id &&
          other.taskId == this.taskId &&
          other.tatsaechlicheDauerMinuten == this.tatsaechlicheDauerMinuten &&
          other.tatsaechlicheMitarbeiter == this.tatsaechlicheMitarbeiter &&
          other.tatsaechlicheMengeKg == this.tatsaechlicheMengeKg &&
          other.verwendeteChargenJson == this.verwendeteChargenJson &&
          other.notizen == this.notizen &&
          other.erfasstVon == this.erfasstVon &&
          other.erfasstAm == this.erfasstAm &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt &&
          other.deletedAt == this.deletedAt);
}

class ProductionRunsCompanion extends UpdateCompanion<ProductionRun> {
  final Value<String> id;
  final Value<String> taskId;
  final Value<double> tatsaechlicheDauerMinuten;
  final Value<int> tatsaechlicheMitarbeiter;
  final Value<double> tatsaechlicheMengeKg;
  final Value<String?> verwendeteChargenJson;
  final Value<String?> notizen;
  final Value<String?> erfasstVon;
  final Value<DateTime> erfasstAm;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<DateTime?> deletedAt;
  final Value<int> rowid;
  const ProductionRunsCompanion({
    this.id = const Value.absent(),
    this.taskId = const Value.absent(),
    this.tatsaechlicheDauerMinuten = const Value.absent(),
    this.tatsaechlicheMitarbeiter = const Value.absent(),
    this.tatsaechlicheMengeKg = const Value.absent(),
    this.verwendeteChargenJson = const Value.absent(),
    this.notizen = const Value.absent(),
    this.erfasstVon = const Value.absent(),
    this.erfasstAm = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ProductionRunsCompanion.insert({
    required String id,
    required String taskId,
    required double tatsaechlicheDauerMinuten,
    required int tatsaechlicheMitarbeiter,
    required double tatsaechlicheMengeKg,
    this.verwendeteChargenJson = const Value.absent(),
    this.notizen = const Value.absent(),
    this.erfasstVon = const Value.absent(),
    this.erfasstAm = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  })  : id = Value(id),
        taskId = Value(taskId),
        tatsaechlicheDauerMinuten = Value(tatsaechlicheDauerMinuten),
        tatsaechlicheMitarbeiter = Value(tatsaechlicheMitarbeiter),
        tatsaechlicheMengeKg = Value(tatsaechlicheMengeKg);
  static Insertable<ProductionRun> custom({
    Expression<String>? id,
    Expression<String>? taskId,
    Expression<double>? tatsaechlicheDauerMinuten,
    Expression<int>? tatsaechlicheMitarbeiter,
    Expression<double>? tatsaechlicheMengeKg,
    Expression<String>? verwendeteChargenJson,
    Expression<String>? notizen,
    Expression<String>? erfasstVon,
    Expression<DateTime>? erfasstAm,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<DateTime>? deletedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (taskId != null) 'task_id': taskId,
      if (tatsaechlicheDauerMinuten != null)
        'tatsaechliche_dauer_minuten': tatsaechlicheDauerMinuten,
      if (tatsaechlicheMitarbeiter != null)
        'tatsaechliche_mitarbeiter': tatsaechlicheMitarbeiter,
      if (tatsaechlicheMengeKg != null)
        'tatsaechliche_menge_kg': tatsaechlicheMengeKg,
      if (verwendeteChargenJson != null)
        'verwendete_chargen_json': verwendeteChargenJson,
      if (notizen != null) 'notizen': notizen,
      if (erfasstVon != null) 'erfasst_von': erfasstVon,
      if (erfasstAm != null) 'erfasst_am': erfasstAm,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (deletedAt != null) 'deleted_at': deletedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ProductionRunsCompanion copyWith(
      {Value<String>? id,
      Value<String>? taskId,
      Value<double>? tatsaechlicheDauerMinuten,
      Value<int>? tatsaechlicheMitarbeiter,
      Value<double>? tatsaechlicheMengeKg,
      Value<String?>? verwendeteChargenJson,
      Value<String?>? notizen,
      Value<String?>? erfasstVon,
      Value<DateTime>? erfasstAm,
      Value<DateTime>? createdAt,
      Value<DateTime>? updatedAt,
      Value<DateTime?>? deletedAt,
      Value<int>? rowid}) {
    return ProductionRunsCompanion(
      id: id ?? this.id,
      taskId: taskId ?? this.taskId,
      tatsaechlicheDauerMinuten:
          tatsaechlicheDauerMinuten ?? this.tatsaechlicheDauerMinuten,
      tatsaechlicheMitarbeiter:
          tatsaechlicheMitarbeiter ?? this.tatsaechlicheMitarbeiter,
      tatsaechlicheMengeKg: tatsaechlicheMengeKg ?? this.tatsaechlicheMengeKg,
      verwendeteChargenJson:
          verwendeteChargenJson ?? this.verwendeteChargenJson,
      notizen: notizen ?? this.notizen,
      erfasstVon: erfasstVon ?? this.erfasstVon,
      erfasstAm: erfasstAm ?? this.erfasstAm,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: deletedAt ?? this.deletedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (taskId.present) {
      map['task_id'] = Variable<String>(taskId.value);
    }
    if (tatsaechlicheDauerMinuten.present) {
      map['tatsaechliche_dauer_minuten'] =
          Variable<double>(tatsaechlicheDauerMinuten.value);
    }
    if (tatsaechlicheMitarbeiter.present) {
      map['tatsaechliche_mitarbeiter'] =
          Variable<int>(tatsaechlicheMitarbeiter.value);
    }
    if (tatsaechlicheMengeKg.present) {
      map['tatsaechliche_menge_kg'] =
          Variable<double>(tatsaechlicheMengeKg.value);
    }
    if (verwendeteChargenJson.present) {
      map['verwendete_chargen_json'] =
          Variable<String>(verwendeteChargenJson.value);
    }
    if (notizen.present) {
      map['notizen'] = Variable<String>(notizen.value);
    }
    if (erfasstVon.present) {
      map['erfasst_von'] = Variable<String>(erfasstVon.value);
    }
    if (erfasstAm.present) {
      map['erfasst_am'] = Variable<DateTime>(erfasstAm.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (deletedAt.present) {
      map['deleted_at'] = Variable<DateTime>(deletedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ProductionRunsCompanion(')
          ..write('id: $id, ')
          ..write('taskId: $taskId, ')
          ..write('tatsaechlicheDauerMinuten: $tatsaechlicheDauerMinuten, ')
          ..write('tatsaechlicheMitarbeiter: $tatsaechlicheMitarbeiter, ')
          ..write('tatsaechlicheMengeKg: $tatsaechlicheMengeKg, ')
          ..write('verwendeteChargenJson: $verwendeteChargenJson, ')
          ..write('notizen: $notizen, ')
          ..write('erfasstVon: $erfasstVon, ')
          ..write('erfasstAm: $erfasstAm, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $TaskDependenciesTable extends TaskDependencies
    with TableInfo<$TaskDependenciesTable, TaskDependency> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $TaskDependenciesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
      'id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _fromTaskIdMeta =
      const VerificationMeta('fromTaskId');
  @override
  late final GeneratedColumn<String> fromTaskId = GeneratedColumn<String>(
      'from_task_id', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: true,
      defaultConstraints: GeneratedColumn.constraintIsAlways(
          'REFERENCES production_tasks (id)'));
  static const VerificationMeta _toTaskIdMeta =
      const VerificationMeta('toTaskId');
  @override
  late final GeneratedColumn<String> toTaskId = GeneratedColumn<String>(
      'to_task_id', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: true,
      defaultConstraints: GeneratedColumn.constraintIsAlways(
          'REFERENCES production_tasks (id)'));
  static const VerificationMeta _typMeta = const VerificationMeta('typ');
  @override
  late final GeneratedColumn<String> typ = GeneratedColumn<String>(
      'typ', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const Constant('finish_to_start'));
  static const VerificationMeta _createdAtMeta =
      const VerificationMeta('createdAt');
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
      'created_at', aliasedName, false,
      type: DriftSqlType.dateTime,
      requiredDuringInsert: false,
      defaultValue: currentDateAndTime);
  static const VerificationMeta _updatedAtMeta =
      const VerificationMeta('updatedAt');
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
      'updated_at', aliasedName, false,
      type: DriftSqlType.dateTime,
      requiredDuringInsert: false,
      defaultValue: currentDateAndTime);
  static const VerificationMeta _deletedAtMeta =
      const VerificationMeta('deletedAt');
  @override
  late final GeneratedColumn<DateTime> deletedAt = GeneratedColumn<DateTime>(
      'deleted_at', aliasedName, true,
      type: DriftSqlType.dateTime, requiredDuringInsert: false);
  @override
  List<GeneratedColumn> get $columns =>
      [id, fromTaskId, toTaskId, typ, createdAt, updatedAt, deletedAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'task_dependencies';
  @override
  VerificationContext validateIntegrity(Insertable<TaskDependency> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('from_task_id')) {
      context.handle(
          _fromTaskIdMeta,
          fromTaskId.isAcceptableOrUnknown(
              data['from_task_id']!, _fromTaskIdMeta));
    } else if (isInserting) {
      context.missing(_fromTaskIdMeta);
    }
    if (data.containsKey('to_task_id')) {
      context.handle(_toTaskIdMeta,
          toTaskId.isAcceptableOrUnknown(data['to_task_id']!, _toTaskIdMeta));
    } else if (isInserting) {
      context.missing(_toTaskIdMeta);
    }
    if (data.containsKey('typ')) {
      context.handle(
          _typMeta, typ.isAcceptableOrUnknown(data['typ']!, _typMeta));
    }
    if (data.containsKey('created_at')) {
      context.handle(_createdAtMeta,
          createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta));
    }
    if (data.containsKey('updated_at')) {
      context.handle(_updatedAtMeta,
          updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta));
    }
    if (data.containsKey('deleted_at')) {
      context.handle(_deletedAtMeta,
          deletedAt.isAcceptableOrUnknown(data['deleted_at']!, _deletedAtMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  TaskDependency map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return TaskDependency(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}id'])!,
      fromTaskId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}from_task_id'])!,
      toTaskId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}to_task_id'])!,
      typ: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}typ'])!,
      createdAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}created_at'])!,
      updatedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}updated_at'])!,
      deletedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}deleted_at']),
    );
  }

  @override
  $TaskDependenciesTable createAlias(String alias) {
    return $TaskDependenciesTable(attachedDatabase, alias);
  }
}

class TaskDependency extends DataClass implements Insertable<TaskDependency> {
  final String id;

  /// Der Task, der wartet.
  final String fromTaskId;

  /// Der Task, auf den gewartet wird.
  final String toTaskId;

  /// Typ der Abhängigkeit. Erlaubte Werte: 'finish_to_start' (Standard),
  /// 'start_to_start', 'finish_to_finish'. Im Fleischbereich reicht
  /// typischerweise 'finish_to_start'.
  final String typ;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;
  const TaskDependency(
      {required this.id,
      required this.fromTaskId,
      required this.toTaskId,
      required this.typ,
      required this.createdAt,
      required this.updatedAt,
      this.deletedAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['from_task_id'] = Variable<String>(fromTaskId);
    map['to_task_id'] = Variable<String>(toTaskId);
    map['typ'] = Variable<String>(typ);
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    if (!nullToAbsent || deletedAt != null) {
      map['deleted_at'] = Variable<DateTime>(deletedAt);
    }
    return map;
  }

  TaskDependenciesCompanion toCompanion(bool nullToAbsent) {
    return TaskDependenciesCompanion(
      id: Value(id),
      fromTaskId: Value(fromTaskId),
      toTaskId: Value(toTaskId),
      typ: Value(typ),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
      deletedAt: deletedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(deletedAt),
    );
  }

  factory TaskDependency.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return TaskDependency(
      id: serializer.fromJson<String>(json['id']),
      fromTaskId: serializer.fromJson<String>(json['fromTaskId']),
      toTaskId: serializer.fromJson<String>(json['toTaskId']),
      typ: serializer.fromJson<String>(json['typ']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
      deletedAt: serializer.fromJson<DateTime?>(json['deletedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'fromTaskId': serializer.toJson<String>(fromTaskId),
      'toTaskId': serializer.toJson<String>(toTaskId),
      'typ': serializer.toJson<String>(typ),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
      'deletedAt': serializer.toJson<DateTime?>(deletedAt),
    };
  }

  TaskDependency copyWith(
          {String? id,
          String? fromTaskId,
          String? toTaskId,
          String? typ,
          DateTime? createdAt,
          DateTime? updatedAt,
          Value<DateTime?> deletedAt = const Value.absent()}) =>
      TaskDependency(
        id: id ?? this.id,
        fromTaskId: fromTaskId ?? this.fromTaskId,
        toTaskId: toTaskId ?? this.toTaskId,
        typ: typ ?? this.typ,
        createdAt: createdAt ?? this.createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
        deletedAt: deletedAt.present ? deletedAt.value : this.deletedAt,
      );
  TaskDependency copyWithCompanion(TaskDependenciesCompanion data) {
    return TaskDependency(
      id: data.id.present ? data.id.value : this.id,
      fromTaskId:
          data.fromTaskId.present ? data.fromTaskId.value : this.fromTaskId,
      toTaskId: data.toTaskId.present ? data.toTaskId.value : this.toTaskId,
      typ: data.typ.present ? data.typ.value : this.typ,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      deletedAt: data.deletedAt.present ? data.deletedAt.value : this.deletedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('TaskDependency(')
          ..write('id: $id, ')
          ..write('fromTaskId: $fromTaskId, ')
          ..write('toTaskId: $toTaskId, ')
          ..write('typ: $typ, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
      id, fromTaskId, toTaskId, typ, createdAt, updatedAt, deletedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is TaskDependency &&
          other.id == this.id &&
          other.fromTaskId == this.fromTaskId &&
          other.toTaskId == this.toTaskId &&
          other.typ == this.typ &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt &&
          other.deletedAt == this.deletedAt);
}

class TaskDependenciesCompanion extends UpdateCompanion<TaskDependency> {
  final Value<String> id;
  final Value<String> fromTaskId;
  final Value<String> toTaskId;
  final Value<String> typ;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<DateTime?> deletedAt;
  final Value<int> rowid;
  const TaskDependenciesCompanion({
    this.id = const Value.absent(),
    this.fromTaskId = const Value.absent(),
    this.toTaskId = const Value.absent(),
    this.typ = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  TaskDependenciesCompanion.insert({
    required String id,
    required String fromTaskId,
    required String toTaskId,
    this.typ = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  })  : id = Value(id),
        fromTaskId = Value(fromTaskId),
        toTaskId = Value(toTaskId);
  static Insertable<TaskDependency> custom({
    Expression<String>? id,
    Expression<String>? fromTaskId,
    Expression<String>? toTaskId,
    Expression<String>? typ,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<DateTime>? deletedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (fromTaskId != null) 'from_task_id': fromTaskId,
      if (toTaskId != null) 'to_task_id': toTaskId,
      if (typ != null) 'typ': typ,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (deletedAt != null) 'deleted_at': deletedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  TaskDependenciesCompanion copyWith(
      {Value<String>? id,
      Value<String>? fromTaskId,
      Value<String>? toTaskId,
      Value<String>? typ,
      Value<DateTime>? createdAt,
      Value<DateTime>? updatedAt,
      Value<DateTime?>? deletedAt,
      Value<int>? rowid}) {
    return TaskDependenciesCompanion(
      id: id ?? this.id,
      fromTaskId: fromTaskId ?? this.fromTaskId,
      toTaskId: toTaskId ?? this.toTaskId,
      typ: typ ?? this.typ,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: deletedAt ?? this.deletedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (fromTaskId.present) {
      map['from_task_id'] = Variable<String>(fromTaskId.value);
    }
    if (toTaskId.present) {
      map['to_task_id'] = Variable<String>(toTaskId.value);
    }
    if (typ.present) {
      map['typ'] = Variable<String>(typ.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (deletedAt.present) {
      map['deleted_at'] = Variable<DateTime>(deletedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('TaskDependenciesCompanion(')
          ..write('id: $id, ')
          ..write('fromTaskId: $fromTaskId, ')
          ..write('toTaskId: $toTaskId, ')
          ..write('typ: $typ, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $OrderListItemsTable extends OrderListItems
    with TableInfo<$OrderListItemsTable, OrderListItem> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $OrderListItemsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
      'id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _rawMaterialIdMeta =
      const VerificationMeta('rawMaterialId');
  @override
  late final GeneratedColumn<String> rawMaterialId = GeneratedColumn<String>(
      'raw_material_id', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: true,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('REFERENCES raw_materials (id)'));
  static const VerificationMeta _wocheStartDatumMeta =
      const VerificationMeta('wocheStartDatum');
  @override
  late final GeneratedColumn<DateTime> wocheStartDatum =
      GeneratedColumn<DateTime>('woche_start_datum', aliasedName, false,
          type: DriftSqlType.dateTime, requiredDuringInsert: true);
  static const VerificationMeta _benoetigteMengeMeta =
      const VerificationMeta('benoetigteMenge');
  @override
  late final GeneratedColumn<double> benoetigteMenge = GeneratedColumn<double>(
      'benoetigte_menge', aliasedName, false,
      type: DriftSqlType.double, requiredDuringInsert: true);
  static const VerificationMeta _einheitMeta =
      const VerificationMeta('einheit');
  @override
  late final GeneratedColumn<String> einheit = GeneratedColumn<String>(
      'einheit', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _bestelltMeta =
      const VerificationMeta('bestellt');
  @override
  late final GeneratedColumn<bool> bestellt = GeneratedColumn<bool>(
      'bestellt', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('CHECK ("bestellt" IN (0, 1))'),
      defaultValue: const Constant(false));
  static const VerificationMeta _bestelltAmMeta =
      const VerificationMeta('bestelltAm');
  @override
  late final GeneratedColumn<DateTime> bestelltAm = GeneratedColumn<DateTime>(
      'bestellt_am', aliasedName, true,
      type: DriftSqlType.dateTime, requiredDuringInsert: false);
  static const VerificationMeta _geliefertMeta =
      const VerificationMeta('geliefert');
  @override
  late final GeneratedColumn<bool> geliefert = GeneratedColumn<bool>(
      'geliefert', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('CHECK ("geliefert" IN (0, 1))'),
      defaultValue: const Constant(false));
  static const VerificationMeta _geliefertAmMeta =
      const VerificationMeta('geliefertAm');
  @override
  late final GeneratedColumn<DateTime> geliefertAm = GeneratedColumn<DateTime>(
      'geliefert_am', aliasedName, true,
      type: DriftSqlType.dateTime, requiredDuringInsert: false);
  static const VerificationMeta _notizenMeta =
      const VerificationMeta('notizen');
  @override
  late final GeneratedColumn<String> notizen = GeneratedColumn<String>(
      'notizen', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _createdAtMeta =
      const VerificationMeta('createdAt');
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
      'created_at', aliasedName, false,
      type: DriftSqlType.dateTime,
      requiredDuringInsert: false,
      defaultValue: currentDateAndTime);
  static const VerificationMeta _updatedAtMeta =
      const VerificationMeta('updatedAt');
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
      'updated_at', aliasedName, false,
      type: DriftSqlType.dateTime,
      requiredDuringInsert: false,
      defaultValue: currentDateAndTime);
  static const VerificationMeta _deletedAtMeta =
      const VerificationMeta('deletedAt');
  @override
  late final GeneratedColumn<DateTime> deletedAt = GeneratedColumn<DateTime>(
      'deleted_at', aliasedName, true,
      type: DriftSqlType.dateTime, requiredDuringInsert: false);
  @override
  List<GeneratedColumn> get $columns => [
        id,
        rawMaterialId,
        wocheStartDatum,
        benoetigteMenge,
        einheit,
        bestellt,
        bestelltAm,
        geliefert,
        geliefertAm,
        notizen,
        createdAt,
        updatedAt,
        deletedAt
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'order_list_items';
  @override
  VerificationContext validateIntegrity(Insertable<OrderListItem> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('raw_material_id')) {
      context.handle(
          _rawMaterialIdMeta,
          rawMaterialId.isAcceptableOrUnknown(
              data['raw_material_id']!, _rawMaterialIdMeta));
    } else if (isInserting) {
      context.missing(_rawMaterialIdMeta);
    }
    if (data.containsKey('woche_start_datum')) {
      context.handle(
          _wocheStartDatumMeta,
          wocheStartDatum.isAcceptableOrUnknown(
              data['woche_start_datum']!, _wocheStartDatumMeta));
    } else if (isInserting) {
      context.missing(_wocheStartDatumMeta);
    }
    if (data.containsKey('benoetigte_menge')) {
      context.handle(
          _benoetigteMengeMeta,
          benoetigteMenge.isAcceptableOrUnknown(
              data['benoetigte_menge']!, _benoetigteMengeMeta));
    } else if (isInserting) {
      context.missing(_benoetigteMengeMeta);
    }
    if (data.containsKey('einheit')) {
      context.handle(_einheitMeta,
          einheit.isAcceptableOrUnknown(data['einheit']!, _einheitMeta));
    } else if (isInserting) {
      context.missing(_einheitMeta);
    }
    if (data.containsKey('bestellt')) {
      context.handle(_bestelltMeta,
          bestellt.isAcceptableOrUnknown(data['bestellt']!, _bestelltMeta));
    }
    if (data.containsKey('bestellt_am')) {
      context.handle(
          _bestelltAmMeta,
          bestelltAm.isAcceptableOrUnknown(
              data['bestellt_am']!, _bestelltAmMeta));
    }
    if (data.containsKey('geliefert')) {
      context.handle(_geliefertMeta,
          geliefert.isAcceptableOrUnknown(data['geliefert']!, _geliefertMeta));
    }
    if (data.containsKey('geliefert_am')) {
      context.handle(
          _geliefertAmMeta,
          geliefertAm.isAcceptableOrUnknown(
              data['geliefert_am']!, _geliefertAmMeta));
    }
    if (data.containsKey('notizen')) {
      context.handle(_notizenMeta,
          notizen.isAcceptableOrUnknown(data['notizen']!, _notizenMeta));
    }
    if (data.containsKey('created_at')) {
      context.handle(_createdAtMeta,
          createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta));
    }
    if (data.containsKey('updated_at')) {
      context.handle(_updatedAtMeta,
          updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta));
    }
    if (data.containsKey('deleted_at')) {
      context.handle(_deletedAtMeta,
          deletedAt.isAcceptableOrUnknown(data['deleted_at']!, _deletedAtMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  OrderListItem map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return OrderListItem(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}id'])!,
      rawMaterialId: attachedDatabase.typeMapping.read(
          DriftSqlType.string, data['${effectivePrefix}raw_material_id'])!,
      wocheStartDatum: attachedDatabase.typeMapping.read(
          DriftSqlType.dateTime, data['${effectivePrefix}woche_start_datum'])!,
      benoetigteMenge: attachedDatabase.typeMapping.read(
          DriftSqlType.double, data['${effectivePrefix}benoetigte_menge'])!,
      einheit: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}einheit'])!,
      bestellt: attachedDatabase.typeMapping
          .read(DriftSqlType.bool, data['${effectivePrefix}bestellt'])!,
      bestelltAm: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}bestellt_am']),
      geliefert: attachedDatabase.typeMapping
          .read(DriftSqlType.bool, data['${effectivePrefix}geliefert'])!,
      geliefertAm: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}geliefert_am']),
      notizen: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}notizen']),
      createdAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}created_at'])!,
      updatedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}updated_at'])!,
      deletedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}deleted_at']),
    );
  }

  @override
  $OrderListItemsTable createAlias(String alias) {
    return $OrderListItemsTable(attachedDatabase, alias);
  }
}

class OrderListItem extends DataClass implements Insertable<OrderListItem> {
  final String id;
  final String rawMaterialId;

  /// Montag der Woche, für die bestellt wird (00:00 Uhr lokal).
  final DateTime wocheStartDatum;
  final double benoetigteMenge;

  /// Denormalisiert aus [RawMaterials.einheit], damit die Liste auch dann
  /// korrekt angezeigt wird, wenn sich die Stammdaten nachträglich ändern.
  final String einheit;
  final bool bestellt;
  final DateTime? bestelltAm;
  final bool geliefert;
  final DateTime? geliefertAm;
  final String? notizen;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;
  const OrderListItem(
      {required this.id,
      required this.rawMaterialId,
      required this.wocheStartDatum,
      required this.benoetigteMenge,
      required this.einheit,
      required this.bestellt,
      this.bestelltAm,
      required this.geliefert,
      this.geliefertAm,
      this.notizen,
      required this.createdAt,
      required this.updatedAt,
      this.deletedAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['raw_material_id'] = Variable<String>(rawMaterialId);
    map['woche_start_datum'] = Variable<DateTime>(wocheStartDatum);
    map['benoetigte_menge'] = Variable<double>(benoetigteMenge);
    map['einheit'] = Variable<String>(einheit);
    map['bestellt'] = Variable<bool>(bestellt);
    if (!nullToAbsent || bestelltAm != null) {
      map['bestellt_am'] = Variable<DateTime>(bestelltAm);
    }
    map['geliefert'] = Variable<bool>(geliefert);
    if (!nullToAbsent || geliefertAm != null) {
      map['geliefert_am'] = Variable<DateTime>(geliefertAm);
    }
    if (!nullToAbsent || notizen != null) {
      map['notizen'] = Variable<String>(notizen);
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    if (!nullToAbsent || deletedAt != null) {
      map['deleted_at'] = Variable<DateTime>(deletedAt);
    }
    return map;
  }

  OrderListItemsCompanion toCompanion(bool nullToAbsent) {
    return OrderListItemsCompanion(
      id: Value(id),
      rawMaterialId: Value(rawMaterialId),
      wocheStartDatum: Value(wocheStartDatum),
      benoetigteMenge: Value(benoetigteMenge),
      einheit: Value(einheit),
      bestellt: Value(bestellt),
      bestelltAm: bestelltAm == null && nullToAbsent
          ? const Value.absent()
          : Value(bestelltAm),
      geliefert: Value(geliefert),
      geliefertAm: geliefertAm == null && nullToAbsent
          ? const Value.absent()
          : Value(geliefertAm),
      notizen: notizen == null && nullToAbsent
          ? const Value.absent()
          : Value(notizen),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
      deletedAt: deletedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(deletedAt),
    );
  }

  factory OrderListItem.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return OrderListItem(
      id: serializer.fromJson<String>(json['id']),
      rawMaterialId: serializer.fromJson<String>(json['rawMaterialId']),
      wocheStartDatum: serializer.fromJson<DateTime>(json['wocheStartDatum']),
      benoetigteMenge: serializer.fromJson<double>(json['benoetigteMenge']),
      einheit: serializer.fromJson<String>(json['einheit']),
      bestellt: serializer.fromJson<bool>(json['bestellt']),
      bestelltAm: serializer.fromJson<DateTime?>(json['bestelltAm']),
      geliefert: serializer.fromJson<bool>(json['geliefert']),
      geliefertAm: serializer.fromJson<DateTime?>(json['geliefertAm']),
      notizen: serializer.fromJson<String?>(json['notizen']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
      deletedAt: serializer.fromJson<DateTime?>(json['deletedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'rawMaterialId': serializer.toJson<String>(rawMaterialId),
      'wocheStartDatum': serializer.toJson<DateTime>(wocheStartDatum),
      'benoetigteMenge': serializer.toJson<double>(benoetigteMenge),
      'einheit': serializer.toJson<String>(einheit),
      'bestellt': serializer.toJson<bool>(bestellt),
      'bestelltAm': serializer.toJson<DateTime?>(bestelltAm),
      'geliefert': serializer.toJson<bool>(geliefert),
      'geliefertAm': serializer.toJson<DateTime?>(geliefertAm),
      'notizen': serializer.toJson<String?>(notizen),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
      'deletedAt': serializer.toJson<DateTime?>(deletedAt),
    };
  }

  OrderListItem copyWith(
          {String? id,
          String? rawMaterialId,
          DateTime? wocheStartDatum,
          double? benoetigteMenge,
          String? einheit,
          bool? bestellt,
          Value<DateTime?> bestelltAm = const Value.absent(),
          bool? geliefert,
          Value<DateTime?> geliefertAm = const Value.absent(),
          Value<String?> notizen = const Value.absent(),
          DateTime? createdAt,
          DateTime? updatedAt,
          Value<DateTime?> deletedAt = const Value.absent()}) =>
      OrderListItem(
        id: id ?? this.id,
        rawMaterialId: rawMaterialId ?? this.rawMaterialId,
        wocheStartDatum: wocheStartDatum ?? this.wocheStartDatum,
        benoetigteMenge: benoetigteMenge ?? this.benoetigteMenge,
        einheit: einheit ?? this.einheit,
        bestellt: bestellt ?? this.bestellt,
        bestelltAm: bestelltAm.present ? bestelltAm.value : this.bestelltAm,
        geliefert: geliefert ?? this.geliefert,
        geliefertAm: geliefertAm.present ? geliefertAm.value : this.geliefertAm,
        notizen: notizen.present ? notizen.value : this.notizen,
        createdAt: createdAt ?? this.createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
        deletedAt: deletedAt.present ? deletedAt.value : this.deletedAt,
      );
  OrderListItem copyWithCompanion(OrderListItemsCompanion data) {
    return OrderListItem(
      id: data.id.present ? data.id.value : this.id,
      rawMaterialId: data.rawMaterialId.present
          ? data.rawMaterialId.value
          : this.rawMaterialId,
      wocheStartDatum: data.wocheStartDatum.present
          ? data.wocheStartDatum.value
          : this.wocheStartDatum,
      benoetigteMenge: data.benoetigteMenge.present
          ? data.benoetigteMenge.value
          : this.benoetigteMenge,
      einheit: data.einheit.present ? data.einheit.value : this.einheit,
      bestellt: data.bestellt.present ? data.bestellt.value : this.bestellt,
      bestelltAm:
          data.bestelltAm.present ? data.bestelltAm.value : this.bestelltAm,
      geliefert: data.geliefert.present ? data.geliefert.value : this.geliefert,
      geliefertAm:
          data.geliefertAm.present ? data.geliefertAm.value : this.geliefertAm,
      notizen: data.notizen.present ? data.notizen.value : this.notizen,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      deletedAt: data.deletedAt.present ? data.deletedAt.value : this.deletedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('OrderListItem(')
          ..write('id: $id, ')
          ..write('rawMaterialId: $rawMaterialId, ')
          ..write('wocheStartDatum: $wocheStartDatum, ')
          ..write('benoetigteMenge: $benoetigteMenge, ')
          ..write('einheit: $einheit, ')
          ..write('bestellt: $bestellt, ')
          ..write('bestelltAm: $bestelltAm, ')
          ..write('geliefert: $geliefert, ')
          ..write('geliefertAm: $geliefertAm, ')
          ..write('notizen: $notizen, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
      id,
      rawMaterialId,
      wocheStartDatum,
      benoetigteMenge,
      einheit,
      bestellt,
      bestelltAm,
      geliefert,
      geliefertAm,
      notizen,
      createdAt,
      updatedAt,
      deletedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is OrderListItem &&
          other.id == this.id &&
          other.rawMaterialId == this.rawMaterialId &&
          other.wocheStartDatum == this.wocheStartDatum &&
          other.benoetigteMenge == this.benoetigteMenge &&
          other.einheit == this.einheit &&
          other.bestellt == this.bestellt &&
          other.bestelltAm == this.bestelltAm &&
          other.geliefert == this.geliefert &&
          other.geliefertAm == this.geliefertAm &&
          other.notizen == this.notizen &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt &&
          other.deletedAt == this.deletedAt);
}

class OrderListItemsCompanion extends UpdateCompanion<OrderListItem> {
  final Value<String> id;
  final Value<String> rawMaterialId;
  final Value<DateTime> wocheStartDatum;
  final Value<double> benoetigteMenge;
  final Value<String> einheit;
  final Value<bool> bestellt;
  final Value<DateTime?> bestelltAm;
  final Value<bool> geliefert;
  final Value<DateTime?> geliefertAm;
  final Value<String?> notizen;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<DateTime?> deletedAt;
  final Value<int> rowid;
  const OrderListItemsCompanion({
    this.id = const Value.absent(),
    this.rawMaterialId = const Value.absent(),
    this.wocheStartDatum = const Value.absent(),
    this.benoetigteMenge = const Value.absent(),
    this.einheit = const Value.absent(),
    this.bestellt = const Value.absent(),
    this.bestelltAm = const Value.absent(),
    this.geliefert = const Value.absent(),
    this.geliefertAm = const Value.absent(),
    this.notizen = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  OrderListItemsCompanion.insert({
    required String id,
    required String rawMaterialId,
    required DateTime wocheStartDatum,
    required double benoetigteMenge,
    required String einheit,
    this.bestellt = const Value.absent(),
    this.bestelltAm = const Value.absent(),
    this.geliefert = const Value.absent(),
    this.geliefertAm = const Value.absent(),
    this.notizen = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  })  : id = Value(id),
        rawMaterialId = Value(rawMaterialId),
        wocheStartDatum = Value(wocheStartDatum),
        benoetigteMenge = Value(benoetigteMenge),
        einheit = Value(einheit);
  static Insertable<OrderListItem> custom({
    Expression<String>? id,
    Expression<String>? rawMaterialId,
    Expression<DateTime>? wocheStartDatum,
    Expression<double>? benoetigteMenge,
    Expression<String>? einheit,
    Expression<bool>? bestellt,
    Expression<DateTime>? bestelltAm,
    Expression<bool>? geliefert,
    Expression<DateTime>? geliefertAm,
    Expression<String>? notizen,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<DateTime>? deletedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (rawMaterialId != null) 'raw_material_id': rawMaterialId,
      if (wocheStartDatum != null) 'woche_start_datum': wocheStartDatum,
      if (benoetigteMenge != null) 'benoetigte_menge': benoetigteMenge,
      if (einheit != null) 'einheit': einheit,
      if (bestellt != null) 'bestellt': bestellt,
      if (bestelltAm != null) 'bestellt_am': bestelltAm,
      if (geliefert != null) 'geliefert': geliefert,
      if (geliefertAm != null) 'geliefert_am': geliefertAm,
      if (notizen != null) 'notizen': notizen,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (deletedAt != null) 'deleted_at': deletedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  OrderListItemsCompanion copyWith(
      {Value<String>? id,
      Value<String>? rawMaterialId,
      Value<DateTime>? wocheStartDatum,
      Value<double>? benoetigteMenge,
      Value<String>? einheit,
      Value<bool>? bestellt,
      Value<DateTime?>? bestelltAm,
      Value<bool>? geliefert,
      Value<DateTime?>? geliefertAm,
      Value<String?>? notizen,
      Value<DateTime>? createdAt,
      Value<DateTime>? updatedAt,
      Value<DateTime?>? deletedAt,
      Value<int>? rowid}) {
    return OrderListItemsCompanion(
      id: id ?? this.id,
      rawMaterialId: rawMaterialId ?? this.rawMaterialId,
      wocheStartDatum: wocheStartDatum ?? this.wocheStartDatum,
      benoetigteMenge: benoetigteMenge ?? this.benoetigteMenge,
      einheit: einheit ?? this.einheit,
      bestellt: bestellt ?? this.bestellt,
      bestelltAm: bestelltAm ?? this.bestelltAm,
      geliefert: geliefert ?? this.geliefert,
      geliefertAm: geliefertAm ?? this.geliefertAm,
      notizen: notizen ?? this.notizen,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: deletedAt ?? this.deletedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (rawMaterialId.present) {
      map['raw_material_id'] = Variable<String>(rawMaterialId.value);
    }
    if (wocheStartDatum.present) {
      map['woche_start_datum'] = Variable<DateTime>(wocheStartDatum.value);
    }
    if (benoetigteMenge.present) {
      map['benoetigte_menge'] = Variable<double>(benoetigteMenge.value);
    }
    if (einheit.present) {
      map['einheit'] = Variable<String>(einheit.value);
    }
    if (bestellt.present) {
      map['bestellt'] = Variable<bool>(bestellt.value);
    }
    if (bestelltAm.present) {
      map['bestellt_am'] = Variable<DateTime>(bestelltAm.value);
    }
    if (geliefert.present) {
      map['geliefert'] = Variable<bool>(geliefert.value);
    }
    if (geliefertAm.present) {
      map['geliefert_am'] = Variable<DateTime>(geliefertAm.value);
    }
    if (notizen.present) {
      map['notizen'] = Variable<String>(notizen.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (deletedAt.present) {
      map['deleted_at'] = Variable<DateTime>(deletedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('OrderListItemsCompanion(')
          ..write('id: $id, ')
          ..write('rawMaterialId: $rawMaterialId, ')
          ..write('wocheStartDatum: $wocheStartDatum, ')
          ..write('benoetigteMenge: $benoetigteMenge, ')
          ..write('einheit: $einheit, ')
          ..write('bestellt: $bestellt, ')
          ..write('bestelltAm: $bestelltAm, ')
          ..write('geliefert: $geliefert, ')
          ..write('geliefertAm: $geliefertAm, ')
          ..write('notizen: $notizen, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $ProductsTable products = $ProductsTable(this);
  late final $ProductStepsTable productSteps = $ProductStepsTable(this);
  late final $RawMaterialsTable rawMaterials = $RawMaterialsTable(this);
  late final $ProductRawMaterialsTable productRawMaterials =
      $ProductRawMaterialsTable(this);
  late final $RawMaterialBatchesTable rawMaterialBatches =
      $RawMaterialBatchesTable(this);
  late final $ProductionTasksTable productionTasks =
      $ProductionTasksTable(this);
  late final $ProductionRunsTable productionRuns = $ProductionRunsTable(this);
  late final $TaskDependenciesTable taskDependencies =
      $TaskDependenciesTable(this);
  late final $OrderListItemsTable orderListItems = $OrderListItemsTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
        products,
        productSteps,
        rawMaterials,
        productRawMaterials,
        rawMaterialBatches,
        productionTasks,
        productionRuns,
        taskDependencies,
        orderListItems
      ];
}

typedef $$ProductsTableCreateCompanionBuilder = ProductsCompanion Function({
  required String id,
  required String artikelnummer,
  required String artikelbezeichnung,
  Value<String?> beschreibung,
  Value<String?> notizen,
  Value<DateTime> createdAt,
  Value<DateTime> updatedAt,
  Value<DateTime?> deletedAt,
  Value<int> rowid,
});
typedef $$ProductsTableUpdateCompanionBuilder = ProductsCompanion Function({
  Value<String> id,
  Value<String> artikelnummer,
  Value<String> artikelbezeichnung,
  Value<String?> beschreibung,
  Value<String?> notizen,
  Value<DateTime> createdAt,
  Value<DateTime> updatedAt,
  Value<DateTime?> deletedAt,
  Value<int> rowid,
});

final class $$ProductsTableReferences
    extends BaseReferences<_$AppDatabase, $ProductsTable, Product> {
  $$ProductsTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static MultiTypedResultKey<$ProductStepsTable, List<ProductStep>>
      _productStepsRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
          db.productSteps,
          aliasName:
              $_aliasNameGenerator(db.products.id, db.productSteps.productId));

  $$ProductStepsTableProcessedTableManager get productStepsRefs {
    final manager = $$ProductStepsTableTableManager($_db, $_db.productSteps)
        .filter((f) => f.productId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_productStepsRefsTable($_db));
    return ProcessedTableManager(
        manager.$state.copyWith(prefetchedData: cache));
  }

  static MultiTypedResultKey<$ProductRawMaterialsTable,
      List<ProductRawMaterial>> _productRawMaterialsRefsTable(
          _$AppDatabase db) =>
      MultiTypedResultKey.fromTable(db.productRawMaterials,
          aliasName: $_aliasNameGenerator(
              db.products.id, db.productRawMaterials.productId));

  $$ProductRawMaterialsTableProcessedTableManager get productRawMaterialsRefs {
    final manager = $$ProductRawMaterialsTableTableManager(
            $_db, $_db.productRawMaterials)
        .filter((f) => f.productId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache =
        $_typedResult.readTableOrNull(_productRawMaterialsRefsTable($_db));
    return ProcessedTableManager(
        manager.$state.copyWith(prefetchedData: cache));
  }

  static MultiTypedResultKey<$ProductionTasksTable, List<ProductionTask>>
      _productionTasksRefsTable(_$AppDatabase db) =>
          MultiTypedResultKey.fromTable(db.productionTasks,
              aliasName: $_aliasNameGenerator(
                  db.products.id, db.productionTasks.productId));

  $$ProductionTasksTableProcessedTableManager get productionTasksRefs {
    final manager = $$ProductionTasksTableTableManager(
            $_db, $_db.productionTasks)
        .filter((f) => f.productId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache =
        $_typedResult.readTableOrNull(_productionTasksRefsTable($_db));
    return ProcessedTableManager(
        manager.$state.copyWith(prefetchedData: cache));
  }
}

class $$ProductsTableFilterComposer
    extends Composer<_$AppDatabase, $ProductsTable> {
  $$ProductsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get artikelnummer => $composableBuilder(
      column: $table.artikelnummer, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get artikelbezeichnung => $composableBuilder(
      column: $table.artikelbezeichnung,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get beschreibung => $composableBuilder(
      column: $table.beschreibung, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get notizen => $composableBuilder(
      column: $table.notizen, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
      column: $table.updatedAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get deletedAt => $composableBuilder(
      column: $table.deletedAt, builder: (column) => ColumnFilters(column));

  Expression<bool> productStepsRefs(
      Expression<bool> Function($$ProductStepsTableFilterComposer f) f) {
    final $$ProductStepsTableFilterComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.id,
        referencedTable: $db.productSteps,
        getReferencedColumn: (t) => t.productId,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$ProductStepsTableFilterComposer(
              $db: $db,
              $table: $db.productSteps,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return f(composer);
  }

  Expression<bool> productRawMaterialsRefs(
      Expression<bool> Function($$ProductRawMaterialsTableFilterComposer f) f) {
    final $$ProductRawMaterialsTableFilterComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.id,
        referencedTable: $db.productRawMaterials,
        getReferencedColumn: (t) => t.productId,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$ProductRawMaterialsTableFilterComposer(
              $db: $db,
              $table: $db.productRawMaterials,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return f(composer);
  }

  Expression<bool> productionTasksRefs(
      Expression<bool> Function($$ProductionTasksTableFilterComposer f) f) {
    final $$ProductionTasksTableFilterComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.id,
        referencedTable: $db.productionTasks,
        getReferencedColumn: (t) => t.productId,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$ProductionTasksTableFilterComposer(
              $db: $db,
              $table: $db.productionTasks,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return f(composer);
  }
}

class $$ProductsTableOrderingComposer
    extends Composer<_$AppDatabase, $ProductsTable> {
  $$ProductsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get artikelnummer => $composableBuilder(
      column: $table.artikelnummer,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get artikelbezeichnung => $composableBuilder(
      column: $table.artikelbezeichnung,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get beschreibung => $composableBuilder(
      column: $table.beschreibung,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get notizen => $composableBuilder(
      column: $table.notizen, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
      column: $table.updatedAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get deletedAt => $composableBuilder(
      column: $table.deletedAt, builder: (column) => ColumnOrderings(column));
}

class $$ProductsTableAnnotationComposer
    extends Composer<_$AppDatabase, $ProductsTable> {
  $$ProductsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get artikelnummer => $composableBuilder(
      column: $table.artikelnummer, builder: (column) => column);

  GeneratedColumn<String> get artikelbezeichnung => $composableBuilder(
      column: $table.artikelbezeichnung, builder: (column) => column);

  GeneratedColumn<String> get beschreibung => $composableBuilder(
      column: $table.beschreibung, builder: (column) => column);

  GeneratedColumn<String> get notizen =>
      $composableBuilder(column: $table.notizen, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<DateTime> get deletedAt =>
      $composableBuilder(column: $table.deletedAt, builder: (column) => column);

  Expression<T> productStepsRefs<T extends Object>(
      Expression<T> Function($$ProductStepsTableAnnotationComposer a) f) {
    final $$ProductStepsTableAnnotationComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.id,
        referencedTable: $db.productSteps,
        getReferencedColumn: (t) => t.productId,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$ProductStepsTableAnnotationComposer(
              $db: $db,
              $table: $db.productSteps,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return f(composer);
  }

  Expression<T> productRawMaterialsRefs<T extends Object>(
      Expression<T> Function($$ProductRawMaterialsTableAnnotationComposer a)
          f) {
    final $$ProductRawMaterialsTableAnnotationComposer composer =
        $composerBuilder(
            composer: this,
            getCurrentColumn: (t) => t.id,
            referencedTable: $db.productRawMaterials,
            getReferencedColumn: (t) => t.productId,
            builder: (joinBuilder,
                    {$addJoinBuilderToRootComposer,
                    $removeJoinBuilderFromRootComposer}) =>
                $$ProductRawMaterialsTableAnnotationComposer(
                  $db: $db,
                  $table: $db.productRawMaterials,
                  $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                  joinBuilder: joinBuilder,
                  $removeJoinBuilderFromRootComposer:
                      $removeJoinBuilderFromRootComposer,
                ));
    return f(composer);
  }

  Expression<T> productionTasksRefs<T extends Object>(
      Expression<T> Function($$ProductionTasksTableAnnotationComposer a) f) {
    final $$ProductionTasksTableAnnotationComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.id,
        referencedTable: $db.productionTasks,
        getReferencedColumn: (t) => t.productId,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$ProductionTasksTableAnnotationComposer(
              $db: $db,
              $table: $db.productionTasks,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return f(composer);
  }
}

class $$ProductsTableTableManager extends RootTableManager<
    _$AppDatabase,
    $ProductsTable,
    Product,
    $$ProductsTableFilterComposer,
    $$ProductsTableOrderingComposer,
    $$ProductsTableAnnotationComposer,
    $$ProductsTableCreateCompanionBuilder,
    $$ProductsTableUpdateCompanionBuilder,
    (Product, $$ProductsTableReferences),
    Product,
    PrefetchHooks Function(
        {bool productStepsRefs,
        bool productRawMaterialsRefs,
        bool productionTasksRefs})> {
  $$ProductsTableTableManager(_$AppDatabase db, $ProductsTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ProductsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ProductsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ProductsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> id = const Value.absent(),
            Value<String> artikelnummer = const Value.absent(),
            Value<String> artikelbezeichnung = const Value.absent(),
            Value<String?> beschreibung = const Value.absent(),
            Value<String?> notizen = const Value.absent(),
            Value<DateTime> createdAt = const Value.absent(),
            Value<DateTime> updatedAt = const Value.absent(),
            Value<DateTime?> deletedAt = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              ProductsCompanion(
            id: id,
            artikelnummer: artikelnummer,
            artikelbezeichnung: artikelbezeichnung,
            beschreibung: beschreibung,
            notizen: notizen,
            createdAt: createdAt,
            updatedAt: updatedAt,
            deletedAt: deletedAt,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String id,
            required String artikelnummer,
            required String artikelbezeichnung,
            Value<String?> beschreibung = const Value.absent(),
            Value<String?> notizen = const Value.absent(),
            Value<DateTime> createdAt = const Value.absent(),
            Value<DateTime> updatedAt = const Value.absent(),
            Value<DateTime?> deletedAt = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              ProductsCompanion.insert(
            id: id,
            artikelnummer: artikelnummer,
            artikelbezeichnung: artikelbezeichnung,
            beschreibung: beschreibung,
            notizen: notizen,
            createdAt: createdAt,
            updatedAt: updatedAt,
            deletedAt: deletedAt,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) =>
                  (e.readTable(table), $$ProductsTableReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: (
              {productStepsRefs = false,
              productRawMaterialsRefs = false,
              productionTasksRefs = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [
                if (productStepsRefs) db.productSteps,
                if (productRawMaterialsRefs) db.productRawMaterials,
                if (productionTasksRefs) db.productionTasks
              ],
              addJoins: null,
              getPrefetchedDataCallback: (items) async {
                return [
                  if (productStepsRefs)
                    await $_getPrefetchedData<Product, $ProductsTable,
                            ProductStep>(
                        currentTable: table,
                        referencedTable: $$ProductsTableReferences
                            ._productStepsRefsTable(db),
                        managerFromTypedResult: (p0) =>
                            $$ProductsTableReferences(db, table, p0)
                                .productStepsRefs,
                        referencedItemsForCurrentItem:
                            (item, referencedItems) => referencedItems
                                .where((e) => e.productId == item.id),
                        typedResults: items),
                  if (productRawMaterialsRefs)
                    await $_getPrefetchedData<Product, $ProductsTable,
                            ProductRawMaterial>(
                        currentTable: table,
                        referencedTable: $$ProductsTableReferences
                            ._productRawMaterialsRefsTable(db),
                        managerFromTypedResult: (p0) =>
                            $$ProductsTableReferences(db, table, p0)
                                .productRawMaterialsRefs,
                        referencedItemsForCurrentItem:
                            (item, referencedItems) => referencedItems
                                .where((e) => e.productId == item.id),
                        typedResults: items),
                  if (productionTasksRefs)
                    await $_getPrefetchedData<Product, $ProductsTable,
                            ProductionTask>(
                        currentTable: table,
                        referencedTable: $$ProductsTableReferences
                            ._productionTasksRefsTable(db),
                        managerFromTypedResult: (p0) =>
                            $$ProductsTableReferences(db, table, p0)
                                .productionTasksRefs,
                        referencedItemsForCurrentItem:
                            (item, referencedItems) => referencedItems
                                .where((e) => e.productId == item.id),
                        typedResults: items)
                ];
              },
            );
          },
        ));
}

typedef $$ProductsTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $ProductsTable,
    Product,
    $$ProductsTableFilterComposer,
    $$ProductsTableOrderingComposer,
    $$ProductsTableAnnotationComposer,
    $$ProductsTableCreateCompanionBuilder,
    $$ProductsTableUpdateCompanionBuilder,
    (Product, $$ProductsTableReferences),
    Product,
    PrefetchHooks Function(
        {bool productStepsRefs,
        bool productRawMaterialsRefs,
        bool productionTasksRefs})>;
typedef $$ProductStepsTableCreateCompanionBuilder = ProductStepsCompanion
    Function({
  required String id,
  required String productId,
  required int reihenfolge,
  required String abteilung,
  required double basisMengeKg,
  required double basisDauerMinuten,
  Value<double?> fixZeitMinuten,
  Value<double?> dauerStdAbweichung,
  required int basisMitarbeiter,
  Value<int> basisAnzahlMessungen,
  Value<String?> maschinenEinstellungenJson,
  Value<String?> notizen,
  Value<DateTime> createdAt,
  Value<DateTime> updatedAt,
  Value<DateTime?> deletedAt,
  Value<int> rowid,
});
typedef $$ProductStepsTableUpdateCompanionBuilder = ProductStepsCompanion
    Function({
  Value<String> id,
  Value<String> productId,
  Value<int> reihenfolge,
  Value<String> abteilung,
  Value<double> basisMengeKg,
  Value<double> basisDauerMinuten,
  Value<double?> fixZeitMinuten,
  Value<double?> dauerStdAbweichung,
  Value<int> basisMitarbeiter,
  Value<int> basisAnzahlMessungen,
  Value<String?> maschinenEinstellungenJson,
  Value<String?> notizen,
  Value<DateTime> createdAt,
  Value<DateTime> updatedAt,
  Value<DateTime?> deletedAt,
  Value<int> rowid,
});

final class $$ProductStepsTableReferences
    extends BaseReferences<_$AppDatabase, $ProductStepsTable, ProductStep> {
  $$ProductStepsTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $ProductsTable _productIdTable(_$AppDatabase db) =>
      db.products.createAlias(
          $_aliasNameGenerator(db.productSteps.productId, db.products.id));

  $$ProductsTableProcessedTableManager get productId {
    final $_column = $_itemColumn<String>('product_id')!;

    final manager = $$ProductsTableTableManager($_db, $_db.products)
        .filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_productIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
        manager.$state.copyWith(prefetchedData: [item]));
  }
}

class $$ProductStepsTableFilterComposer
    extends Composer<_$AppDatabase, $ProductStepsTable> {
  $$ProductStepsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get reihenfolge => $composableBuilder(
      column: $table.reihenfolge, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get abteilung => $composableBuilder(
      column: $table.abteilung, builder: (column) => ColumnFilters(column));

  ColumnFilters<double> get basisMengeKg => $composableBuilder(
      column: $table.basisMengeKg, builder: (column) => ColumnFilters(column));

  ColumnFilters<double> get basisDauerMinuten => $composableBuilder(
      column: $table.basisDauerMinuten,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<double> get fixZeitMinuten => $composableBuilder(
      column: $table.fixZeitMinuten,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<double> get dauerStdAbweichung => $composableBuilder(
      column: $table.dauerStdAbweichung,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get basisMitarbeiter => $composableBuilder(
      column: $table.basisMitarbeiter,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get basisAnzahlMessungen => $composableBuilder(
      column: $table.basisAnzahlMessungen,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get maschinenEinstellungenJson => $composableBuilder(
      column: $table.maschinenEinstellungenJson,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get notizen => $composableBuilder(
      column: $table.notizen, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
      column: $table.updatedAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get deletedAt => $composableBuilder(
      column: $table.deletedAt, builder: (column) => ColumnFilters(column));

  $$ProductsTableFilterComposer get productId {
    final $$ProductsTableFilterComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.productId,
        referencedTable: $db.products,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$ProductsTableFilterComposer(
              $db: $db,
              $table: $db.products,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }
}

class $$ProductStepsTableOrderingComposer
    extends Composer<_$AppDatabase, $ProductStepsTable> {
  $$ProductStepsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get reihenfolge => $composableBuilder(
      column: $table.reihenfolge, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get abteilung => $composableBuilder(
      column: $table.abteilung, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<double> get basisMengeKg => $composableBuilder(
      column: $table.basisMengeKg,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<double> get basisDauerMinuten => $composableBuilder(
      column: $table.basisDauerMinuten,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<double> get fixZeitMinuten => $composableBuilder(
      column: $table.fixZeitMinuten,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<double> get dauerStdAbweichung => $composableBuilder(
      column: $table.dauerStdAbweichung,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get basisMitarbeiter => $composableBuilder(
      column: $table.basisMitarbeiter,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get basisAnzahlMessungen => $composableBuilder(
      column: $table.basisAnzahlMessungen,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get maschinenEinstellungenJson => $composableBuilder(
      column: $table.maschinenEinstellungenJson,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get notizen => $composableBuilder(
      column: $table.notizen, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
      column: $table.updatedAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get deletedAt => $composableBuilder(
      column: $table.deletedAt, builder: (column) => ColumnOrderings(column));

  $$ProductsTableOrderingComposer get productId {
    final $$ProductsTableOrderingComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.productId,
        referencedTable: $db.products,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$ProductsTableOrderingComposer(
              $db: $db,
              $table: $db.products,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }
}

class $$ProductStepsTableAnnotationComposer
    extends Composer<_$AppDatabase, $ProductStepsTable> {
  $$ProductStepsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<int> get reihenfolge => $composableBuilder(
      column: $table.reihenfolge, builder: (column) => column);

  GeneratedColumn<String> get abteilung =>
      $composableBuilder(column: $table.abteilung, builder: (column) => column);

  GeneratedColumn<double> get basisMengeKg => $composableBuilder(
      column: $table.basisMengeKg, builder: (column) => column);

  GeneratedColumn<double> get basisDauerMinuten => $composableBuilder(
      column: $table.basisDauerMinuten, builder: (column) => column);

  GeneratedColumn<double> get fixZeitMinuten => $composableBuilder(
      column: $table.fixZeitMinuten, builder: (column) => column);

  GeneratedColumn<double> get dauerStdAbweichung => $composableBuilder(
      column: $table.dauerStdAbweichung, builder: (column) => column);

  GeneratedColumn<int> get basisMitarbeiter => $composableBuilder(
      column: $table.basisMitarbeiter, builder: (column) => column);

  GeneratedColumn<int> get basisAnzahlMessungen => $composableBuilder(
      column: $table.basisAnzahlMessungen, builder: (column) => column);

  GeneratedColumn<String> get maschinenEinstellungenJson => $composableBuilder(
      column: $table.maschinenEinstellungenJson, builder: (column) => column);

  GeneratedColumn<String> get notizen =>
      $composableBuilder(column: $table.notizen, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<DateTime> get deletedAt =>
      $composableBuilder(column: $table.deletedAt, builder: (column) => column);

  $$ProductsTableAnnotationComposer get productId {
    final $$ProductsTableAnnotationComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.productId,
        referencedTable: $db.products,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$ProductsTableAnnotationComposer(
              $db: $db,
              $table: $db.products,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }
}

class $$ProductStepsTableTableManager extends RootTableManager<
    _$AppDatabase,
    $ProductStepsTable,
    ProductStep,
    $$ProductStepsTableFilterComposer,
    $$ProductStepsTableOrderingComposer,
    $$ProductStepsTableAnnotationComposer,
    $$ProductStepsTableCreateCompanionBuilder,
    $$ProductStepsTableUpdateCompanionBuilder,
    (ProductStep, $$ProductStepsTableReferences),
    ProductStep,
    PrefetchHooks Function({bool productId})> {
  $$ProductStepsTableTableManager(_$AppDatabase db, $ProductStepsTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ProductStepsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ProductStepsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ProductStepsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> id = const Value.absent(),
            Value<String> productId = const Value.absent(),
            Value<int> reihenfolge = const Value.absent(),
            Value<String> abteilung = const Value.absent(),
            Value<double> basisMengeKg = const Value.absent(),
            Value<double> basisDauerMinuten = const Value.absent(),
            Value<double?> fixZeitMinuten = const Value.absent(),
            Value<double?> dauerStdAbweichung = const Value.absent(),
            Value<int> basisMitarbeiter = const Value.absent(),
            Value<int> basisAnzahlMessungen = const Value.absent(),
            Value<String?> maschinenEinstellungenJson = const Value.absent(),
            Value<String?> notizen = const Value.absent(),
            Value<DateTime> createdAt = const Value.absent(),
            Value<DateTime> updatedAt = const Value.absent(),
            Value<DateTime?> deletedAt = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              ProductStepsCompanion(
            id: id,
            productId: productId,
            reihenfolge: reihenfolge,
            abteilung: abteilung,
            basisMengeKg: basisMengeKg,
            basisDauerMinuten: basisDauerMinuten,
            fixZeitMinuten: fixZeitMinuten,
            dauerStdAbweichung: dauerStdAbweichung,
            basisMitarbeiter: basisMitarbeiter,
            basisAnzahlMessungen: basisAnzahlMessungen,
            maschinenEinstellungenJson: maschinenEinstellungenJson,
            notizen: notizen,
            createdAt: createdAt,
            updatedAt: updatedAt,
            deletedAt: deletedAt,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String id,
            required String productId,
            required int reihenfolge,
            required String abteilung,
            required double basisMengeKg,
            required double basisDauerMinuten,
            Value<double?> fixZeitMinuten = const Value.absent(),
            Value<double?> dauerStdAbweichung = const Value.absent(),
            required int basisMitarbeiter,
            Value<int> basisAnzahlMessungen = const Value.absent(),
            Value<String?> maschinenEinstellungenJson = const Value.absent(),
            Value<String?> notizen = const Value.absent(),
            Value<DateTime> createdAt = const Value.absent(),
            Value<DateTime> updatedAt = const Value.absent(),
            Value<DateTime?> deletedAt = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              ProductStepsCompanion.insert(
            id: id,
            productId: productId,
            reihenfolge: reihenfolge,
            abteilung: abteilung,
            basisMengeKg: basisMengeKg,
            basisDauerMinuten: basisDauerMinuten,
            fixZeitMinuten: fixZeitMinuten,
            dauerStdAbweichung: dauerStdAbweichung,
            basisMitarbeiter: basisMitarbeiter,
            basisAnzahlMessungen: basisAnzahlMessungen,
            maschinenEinstellungenJson: maschinenEinstellungenJson,
            notizen: notizen,
            createdAt: createdAt,
            updatedAt: updatedAt,
            deletedAt: deletedAt,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (
                    e.readTable(table),
                    $$ProductStepsTableReferences(db, table, e)
                  ))
              .toList(),
          prefetchHooksCallback: ({productId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins: <
                  T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic>>(state) {
                if (productId) {
                  state = state.withJoin(
                    currentTable: table,
                    currentColumn: table.productId,
                    referencedTable:
                        $$ProductStepsTableReferences._productIdTable(db),
                    referencedColumn:
                        $$ProductStepsTableReferences._productIdTable(db).id,
                  ) as T;
                }

                return state;
              },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ));
}

typedef $$ProductStepsTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $ProductStepsTable,
    ProductStep,
    $$ProductStepsTableFilterComposer,
    $$ProductStepsTableOrderingComposer,
    $$ProductStepsTableAnnotationComposer,
    $$ProductStepsTableCreateCompanionBuilder,
    $$ProductStepsTableUpdateCompanionBuilder,
    (ProductStep, $$ProductStepsTableReferences),
    ProductStep,
    PrefetchHooks Function({bool productId})>;
typedef $$RawMaterialsTableCreateCompanionBuilder = RawMaterialsCompanion
    Function({
  required String id,
  required String name,
  Value<String?> artikelnummer,
  required String einheit,
  Value<String?> lieferant,
  Value<int?> leadTimeTage,
  Value<bool> chargenPflicht,
  Value<String?> notizen,
  Value<DateTime> createdAt,
  Value<DateTime> updatedAt,
  Value<DateTime?> deletedAt,
  Value<int> rowid,
});
typedef $$RawMaterialsTableUpdateCompanionBuilder = RawMaterialsCompanion
    Function({
  Value<String> id,
  Value<String> name,
  Value<String?> artikelnummer,
  Value<String> einheit,
  Value<String?> lieferant,
  Value<int?> leadTimeTage,
  Value<bool> chargenPflicht,
  Value<String?> notizen,
  Value<DateTime> createdAt,
  Value<DateTime> updatedAt,
  Value<DateTime?> deletedAt,
  Value<int> rowid,
});

final class $$RawMaterialsTableReferences
    extends BaseReferences<_$AppDatabase, $RawMaterialsTable, RawMaterial> {
  $$RawMaterialsTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static MultiTypedResultKey<$ProductRawMaterialsTable,
      List<ProductRawMaterial>> _productRawMaterialsRefsTable(
          _$AppDatabase db) =>
      MultiTypedResultKey.fromTable(db.productRawMaterials,
          aliasName: $_aliasNameGenerator(
              db.rawMaterials.id, db.productRawMaterials.rawMaterialId));

  $$ProductRawMaterialsTableProcessedTableManager get productRawMaterialsRefs {
    final manager = $$ProductRawMaterialsTableTableManager(
            $_db, $_db.productRawMaterials)
        .filter(
            (f) => f.rawMaterialId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache =
        $_typedResult.readTableOrNull(_productRawMaterialsRefsTable($_db));
    return ProcessedTableManager(
        manager.$state.copyWith(prefetchedData: cache));
  }

  static MultiTypedResultKey<$RawMaterialBatchesTable, List<RawMaterialBatche>>
      _rawMaterialBatchesRefsTable(_$AppDatabase db) =>
          MultiTypedResultKey.fromTable(db.rawMaterialBatches,
              aliasName: $_aliasNameGenerator(
                  db.rawMaterials.id, db.rawMaterialBatches.rawMaterialId));

  $$RawMaterialBatchesTableProcessedTableManager get rawMaterialBatchesRefs {
    final manager = $$RawMaterialBatchesTableTableManager(
            $_db, $_db.rawMaterialBatches)
        .filter(
            (f) => f.rawMaterialId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache =
        $_typedResult.readTableOrNull(_rawMaterialBatchesRefsTable($_db));
    return ProcessedTableManager(
        manager.$state.copyWith(prefetchedData: cache));
  }

  static MultiTypedResultKey<$OrderListItemsTable, List<OrderListItem>>
      _orderListItemsRefsTable(_$AppDatabase db) =>
          MultiTypedResultKey.fromTable(db.orderListItems,
              aliasName: $_aliasNameGenerator(
                  db.rawMaterials.id, db.orderListItems.rawMaterialId));

  $$OrderListItemsTableProcessedTableManager get orderListItemsRefs {
    final manager = $$OrderListItemsTableTableManager($_db, $_db.orderListItems)
        .filter(
            (f) => f.rawMaterialId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_orderListItemsRefsTable($_db));
    return ProcessedTableManager(
        manager.$state.copyWith(prefetchedData: cache));
  }
}

class $$RawMaterialsTableFilterComposer
    extends Composer<_$AppDatabase, $RawMaterialsTable> {
  $$RawMaterialsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get name => $composableBuilder(
      column: $table.name, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get artikelnummer => $composableBuilder(
      column: $table.artikelnummer, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get einheit => $composableBuilder(
      column: $table.einheit, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get lieferant => $composableBuilder(
      column: $table.lieferant, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get leadTimeTage => $composableBuilder(
      column: $table.leadTimeTage, builder: (column) => ColumnFilters(column));

  ColumnFilters<bool> get chargenPflicht => $composableBuilder(
      column: $table.chargenPflicht,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get notizen => $composableBuilder(
      column: $table.notizen, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
      column: $table.updatedAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get deletedAt => $composableBuilder(
      column: $table.deletedAt, builder: (column) => ColumnFilters(column));

  Expression<bool> productRawMaterialsRefs(
      Expression<bool> Function($$ProductRawMaterialsTableFilterComposer f) f) {
    final $$ProductRawMaterialsTableFilterComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.id,
        referencedTable: $db.productRawMaterials,
        getReferencedColumn: (t) => t.rawMaterialId,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$ProductRawMaterialsTableFilterComposer(
              $db: $db,
              $table: $db.productRawMaterials,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return f(composer);
  }

  Expression<bool> rawMaterialBatchesRefs(
      Expression<bool> Function($$RawMaterialBatchesTableFilterComposer f) f) {
    final $$RawMaterialBatchesTableFilterComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.id,
        referencedTable: $db.rawMaterialBatches,
        getReferencedColumn: (t) => t.rawMaterialId,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$RawMaterialBatchesTableFilterComposer(
              $db: $db,
              $table: $db.rawMaterialBatches,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return f(composer);
  }

  Expression<bool> orderListItemsRefs(
      Expression<bool> Function($$OrderListItemsTableFilterComposer f) f) {
    final $$OrderListItemsTableFilterComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.id,
        referencedTable: $db.orderListItems,
        getReferencedColumn: (t) => t.rawMaterialId,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$OrderListItemsTableFilterComposer(
              $db: $db,
              $table: $db.orderListItems,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return f(composer);
  }
}

class $$RawMaterialsTableOrderingComposer
    extends Composer<_$AppDatabase, $RawMaterialsTable> {
  $$RawMaterialsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get name => $composableBuilder(
      column: $table.name, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get artikelnummer => $composableBuilder(
      column: $table.artikelnummer,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get einheit => $composableBuilder(
      column: $table.einheit, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get lieferant => $composableBuilder(
      column: $table.lieferant, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get leadTimeTage => $composableBuilder(
      column: $table.leadTimeTage,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<bool> get chargenPflicht => $composableBuilder(
      column: $table.chargenPflicht,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get notizen => $composableBuilder(
      column: $table.notizen, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
      column: $table.updatedAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get deletedAt => $composableBuilder(
      column: $table.deletedAt, builder: (column) => ColumnOrderings(column));
}

class $$RawMaterialsTableAnnotationComposer
    extends Composer<_$AppDatabase, $RawMaterialsTable> {
  $$RawMaterialsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get artikelnummer => $composableBuilder(
      column: $table.artikelnummer, builder: (column) => column);

  GeneratedColumn<String> get einheit =>
      $composableBuilder(column: $table.einheit, builder: (column) => column);

  GeneratedColumn<String> get lieferant =>
      $composableBuilder(column: $table.lieferant, builder: (column) => column);

  GeneratedColumn<int> get leadTimeTage => $composableBuilder(
      column: $table.leadTimeTage, builder: (column) => column);

  GeneratedColumn<bool> get chargenPflicht => $composableBuilder(
      column: $table.chargenPflicht, builder: (column) => column);

  GeneratedColumn<String> get notizen =>
      $composableBuilder(column: $table.notizen, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<DateTime> get deletedAt =>
      $composableBuilder(column: $table.deletedAt, builder: (column) => column);

  Expression<T> productRawMaterialsRefs<T extends Object>(
      Expression<T> Function($$ProductRawMaterialsTableAnnotationComposer a)
          f) {
    final $$ProductRawMaterialsTableAnnotationComposer composer =
        $composerBuilder(
            composer: this,
            getCurrentColumn: (t) => t.id,
            referencedTable: $db.productRawMaterials,
            getReferencedColumn: (t) => t.rawMaterialId,
            builder: (joinBuilder,
                    {$addJoinBuilderToRootComposer,
                    $removeJoinBuilderFromRootComposer}) =>
                $$ProductRawMaterialsTableAnnotationComposer(
                  $db: $db,
                  $table: $db.productRawMaterials,
                  $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                  joinBuilder: joinBuilder,
                  $removeJoinBuilderFromRootComposer:
                      $removeJoinBuilderFromRootComposer,
                ));
    return f(composer);
  }

  Expression<T> rawMaterialBatchesRefs<T extends Object>(
      Expression<T> Function($$RawMaterialBatchesTableAnnotationComposer a) f) {
    final $$RawMaterialBatchesTableAnnotationComposer composer =
        $composerBuilder(
            composer: this,
            getCurrentColumn: (t) => t.id,
            referencedTable: $db.rawMaterialBatches,
            getReferencedColumn: (t) => t.rawMaterialId,
            builder: (joinBuilder,
                    {$addJoinBuilderToRootComposer,
                    $removeJoinBuilderFromRootComposer}) =>
                $$RawMaterialBatchesTableAnnotationComposer(
                  $db: $db,
                  $table: $db.rawMaterialBatches,
                  $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                  joinBuilder: joinBuilder,
                  $removeJoinBuilderFromRootComposer:
                      $removeJoinBuilderFromRootComposer,
                ));
    return f(composer);
  }

  Expression<T> orderListItemsRefs<T extends Object>(
      Expression<T> Function($$OrderListItemsTableAnnotationComposer a) f) {
    final $$OrderListItemsTableAnnotationComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.id,
        referencedTable: $db.orderListItems,
        getReferencedColumn: (t) => t.rawMaterialId,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$OrderListItemsTableAnnotationComposer(
              $db: $db,
              $table: $db.orderListItems,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return f(composer);
  }
}

class $$RawMaterialsTableTableManager extends RootTableManager<
    _$AppDatabase,
    $RawMaterialsTable,
    RawMaterial,
    $$RawMaterialsTableFilterComposer,
    $$RawMaterialsTableOrderingComposer,
    $$RawMaterialsTableAnnotationComposer,
    $$RawMaterialsTableCreateCompanionBuilder,
    $$RawMaterialsTableUpdateCompanionBuilder,
    (RawMaterial, $$RawMaterialsTableReferences),
    RawMaterial,
    PrefetchHooks Function(
        {bool productRawMaterialsRefs,
        bool rawMaterialBatchesRefs,
        bool orderListItemsRefs})> {
  $$RawMaterialsTableTableManager(_$AppDatabase db, $RawMaterialsTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$RawMaterialsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$RawMaterialsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$RawMaterialsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> id = const Value.absent(),
            Value<String> name = const Value.absent(),
            Value<String?> artikelnummer = const Value.absent(),
            Value<String> einheit = const Value.absent(),
            Value<String?> lieferant = const Value.absent(),
            Value<int?> leadTimeTage = const Value.absent(),
            Value<bool> chargenPflicht = const Value.absent(),
            Value<String?> notizen = const Value.absent(),
            Value<DateTime> createdAt = const Value.absent(),
            Value<DateTime> updatedAt = const Value.absent(),
            Value<DateTime?> deletedAt = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              RawMaterialsCompanion(
            id: id,
            name: name,
            artikelnummer: artikelnummer,
            einheit: einheit,
            lieferant: lieferant,
            leadTimeTage: leadTimeTage,
            chargenPflicht: chargenPflicht,
            notizen: notizen,
            createdAt: createdAt,
            updatedAt: updatedAt,
            deletedAt: deletedAt,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String id,
            required String name,
            Value<String?> artikelnummer = const Value.absent(),
            required String einheit,
            Value<String?> lieferant = const Value.absent(),
            Value<int?> leadTimeTage = const Value.absent(),
            Value<bool> chargenPflicht = const Value.absent(),
            Value<String?> notizen = const Value.absent(),
            Value<DateTime> createdAt = const Value.absent(),
            Value<DateTime> updatedAt = const Value.absent(),
            Value<DateTime?> deletedAt = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              RawMaterialsCompanion.insert(
            id: id,
            name: name,
            artikelnummer: artikelnummer,
            einheit: einheit,
            lieferant: lieferant,
            leadTimeTage: leadTimeTage,
            chargenPflicht: chargenPflicht,
            notizen: notizen,
            createdAt: createdAt,
            updatedAt: updatedAt,
            deletedAt: deletedAt,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (
                    e.readTable(table),
                    $$RawMaterialsTableReferences(db, table, e)
                  ))
              .toList(),
          prefetchHooksCallback: (
              {productRawMaterialsRefs = false,
              rawMaterialBatchesRefs = false,
              orderListItemsRefs = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [
                if (productRawMaterialsRefs) db.productRawMaterials,
                if (rawMaterialBatchesRefs) db.rawMaterialBatches,
                if (orderListItemsRefs) db.orderListItems
              ],
              addJoins: null,
              getPrefetchedDataCallback: (items) async {
                return [
                  if (productRawMaterialsRefs)
                    await $_getPrefetchedData<RawMaterial, $RawMaterialsTable,
                            ProductRawMaterial>(
                        currentTable: table,
                        referencedTable: $$RawMaterialsTableReferences
                            ._productRawMaterialsRefsTable(db),
                        managerFromTypedResult: (p0) =>
                            $$RawMaterialsTableReferences(db, table, p0)
                                .productRawMaterialsRefs,
                        referencedItemsForCurrentItem:
                            (item, referencedItems) => referencedItems
                                .where((e) => e.rawMaterialId == item.id),
                        typedResults: items),
                  if (rawMaterialBatchesRefs)
                    await $_getPrefetchedData<RawMaterial, $RawMaterialsTable,
                            RawMaterialBatche>(
                        currentTable: table,
                        referencedTable: $$RawMaterialsTableReferences
                            ._rawMaterialBatchesRefsTable(db),
                        managerFromTypedResult: (p0) =>
                            $$RawMaterialsTableReferences(db, table, p0)
                                .rawMaterialBatchesRefs,
                        referencedItemsForCurrentItem:
                            (item, referencedItems) => referencedItems
                                .where((e) => e.rawMaterialId == item.id),
                        typedResults: items),
                  if (orderListItemsRefs)
                    await $_getPrefetchedData<RawMaterial, $RawMaterialsTable,
                            OrderListItem>(
                        currentTable: table,
                        referencedTable: $$RawMaterialsTableReferences
                            ._orderListItemsRefsTable(db),
                        managerFromTypedResult: (p0) =>
                            $$RawMaterialsTableReferences(db, table, p0)
                                .orderListItemsRefs,
                        referencedItemsForCurrentItem:
                            (item, referencedItems) => referencedItems
                                .where((e) => e.rawMaterialId == item.id),
                        typedResults: items)
                ];
              },
            );
          },
        ));
}

typedef $$RawMaterialsTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $RawMaterialsTable,
    RawMaterial,
    $$RawMaterialsTableFilterComposer,
    $$RawMaterialsTableOrderingComposer,
    $$RawMaterialsTableAnnotationComposer,
    $$RawMaterialsTableCreateCompanionBuilder,
    $$RawMaterialsTableUpdateCompanionBuilder,
    (RawMaterial, $$RawMaterialsTableReferences),
    RawMaterial,
    PrefetchHooks Function(
        {bool productRawMaterialsRefs,
        bool rawMaterialBatchesRefs,
        bool orderListItemsRefs})>;
typedef $$ProductRawMaterialsTableCreateCompanionBuilder
    = ProductRawMaterialsCompanion Function({
  required String id,
  required String productId,
  required String rawMaterialId,
  required double mengeProKgProdukt,
  Value<double?> toleranzProzent,
  Value<String?> notizen,
  Value<DateTime> createdAt,
  Value<DateTime> updatedAt,
  Value<DateTime?> deletedAt,
  Value<int> rowid,
});
typedef $$ProductRawMaterialsTableUpdateCompanionBuilder
    = ProductRawMaterialsCompanion Function({
  Value<String> id,
  Value<String> productId,
  Value<String> rawMaterialId,
  Value<double> mengeProKgProdukt,
  Value<double?> toleranzProzent,
  Value<String?> notizen,
  Value<DateTime> createdAt,
  Value<DateTime> updatedAt,
  Value<DateTime?> deletedAt,
  Value<int> rowid,
});

final class $$ProductRawMaterialsTableReferences extends BaseReferences<
    _$AppDatabase, $ProductRawMaterialsTable, ProductRawMaterial> {
  $$ProductRawMaterialsTableReferences(
      super.$_db, super.$_table, super.$_typedResult);

  static $ProductsTable _productIdTable(_$AppDatabase db) =>
      db.products.createAlias($_aliasNameGenerator(
          db.productRawMaterials.productId, db.products.id));

  $$ProductsTableProcessedTableManager get productId {
    final $_column = $_itemColumn<String>('product_id')!;

    final manager = $$ProductsTableTableManager($_db, $_db.products)
        .filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_productIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
        manager.$state.copyWith(prefetchedData: [item]));
  }

  static $RawMaterialsTable _rawMaterialIdTable(_$AppDatabase db) =>
      db.rawMaterials.createAlias($_aliasNameGenerator(
          db.productRawMaterials.rawMaterialId, db.rawMaterials.id));

  $$RawMaterialsTableProcessedTableManager get rawMaterialId {
    final $_column = $_itemColumn<String>('raw_material_id')!;

    final manager = $$RawMaterialsTableTableManager($_db, $_db.rawMaterials)
        .filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_rawMaterialIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
        manager.$state.copyWith(prefetchedData: [item]));
  }
}

class $$ProductRawMaterialsTableFilterComposer
    extends Composer<_$AppDatabase, $ProductRawMaterialsTable> {
  $$ProductRawMaterialsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<double> get mengeProKgProdukt => $composableBuilder(
      column: $table.mengeProKgProdukt,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<double> get toleranzProzent => $composableBuilder(
      column: $table.toleranzProzent,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get notizen => $composableBuilder(
      column: $table.notizen, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
      column: $table.updatedAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get deletedAt => $composableBuilder(
      column: $table.deletedAt, builder: (column) => ColumnFilters(column));

  $$ProductsTableFilterComposer get productId {
    final $$ProductsTableFilterComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.productId,
        referencedTable: $db.products,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$ProductsTableFilterComposer(
              $db: $db,
              $table: $db.products,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }

  $$RawMaterialsTableFilterComposer get rawMaterialId {
    final $$RawMaterialsTableFilterComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.rawMaterialId,
        referencedTable: $db.rawMaterials,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$RawMaterialsTableFilterComposer(
              $db: $db,
              $table: $db.rawMaterials,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }
}

class $$ProductRawMaterialsTableOrderingComposer
    extends Composer<_$AppDatabase, $ProductRawMaterialsTable> {
  $$ProductRawMaterialsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<double> get mengeProKgProdukt => $composableBuilder(
      column: $table.mengeProKgProdukt,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<double> get toleranzProzent => $composableBuilder(
      column: $table.toleranzProzent,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get notizen => $composableBuilder(
      column: $table.notizen, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
      column: $table.updatedAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get deletedAt => $composableBuilder(
      column: $table.deletedAt, builder: (column) => ColumnOrderings(column));

  $$ProductsTableOrderingComposer get productId {
    final $$ProductsTableOrderingComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.productId,
        referencedTable: $db.products,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$ProductsTableOrderingComposer(
              $db: $db,
              $table: $db.products,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }

  $$RawMaterialsTableOrderingComposer get rawMaterialId {
    final $$RawMaterialsTableOrderingComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.rawMaterialId,
        referencedTable: $db.rawMaterials,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$RawMaterialsTableOrderingComposer(
              $db: $db,
              $table: $db.rawMaterials,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }
}

class $$ProductRawMaterialsTableAnnotationComposer
    extends Composer<_$AppDatabase, $ProductRawMaterialsTable> {
  $$ProductRawMaterialsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<double> get mengeProKgProdukt => $composableBuilder(
      column: $table.mengeProKgProdukt, builder: (column) => column);

  GeneratedColumn<double> get toleranzProzent => $composableBuilder(
      column: $table.toleranzProzent, builder: (column) => column);

  GeneratedColumn<String> get notizen =>
      $composableBuilder(column: $table.notizen, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<DateTime> get deletedAt =>
      $composableBuilder(column: $table.deletedAt, builder: (column) => column);

  $$ProductsTableAnnotationComposer get productId {
    final $$ProductsTableAnnotationComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.productId,
        referencedTable: $db.products,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$ProductsTableAnnotationComposer(
              $db: $db,
              $table: $db.products,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }

  $$RawMaterialsTableAnnotationComposer get rawMaterialId {
    final $$RawMaterialsTableAnnotationComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.rawMaterialId,
        referencedTable: $db.rawMaterials,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$RawMaterialsTableAnnotationComposer(
              $db: $db,
              $table: $db.rawMaterials,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }
}

class $$ProductRawMaterialsTableTableManager extends RootTableManager<
    _$AppDatabase,
    $ProductRawMaterialsTable,
    ProductRawMaterial,
    $$ProductRawMaterialsTableFilterComposer,
    $$ProductRawMaterialsTableOrderingComposer,
    $$ProductRawMaterialsTableAnnotationComposer,
    $$ProductRawMaterialsTableCreateCompanionBuilder,
    $$ProductRawMaterialsTableUpdateCompanionBuilder,
    (ProductRawMaterial, $$ProductRawMaterialsTableReferences),
    ProductRawMaterial,
    PrefetchHooks Function({bool productId, bool rawMaterialId})> {
  $$ProductRawMaterialsTableTableManager(
      _$AppDatabase db, $ProductRawMaterialsTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ProductRawMaterialsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ProductRawMaterialsTableOrderingComposer(
                  $db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ProductRawMaterialsTableAnnotationComposer(
                  $db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> id = const Value.absent(),
            Value<String> productId = const Value.absent(),
            Value<String> rawMaterialId = const Value.absent(),
            Value<double> mengeProKgProdukt = const Value.absent(),
            Value<double?> toleranzProzent = const Value.absent(),
            Value<String?> notizen = const Value.absent(),
            Value<DateTime> createdAt = const Value.absent(),
            Value<DateTime> updatedAt = const Value.absent(),
            Value<DateTime?> deletedAt = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              ProductRawMaterialsCompanion(
            id: id,
            productId: productId,
            rawMaterialId: rawMaterialId,
            mengeProKgProdukt: mengeProKgProdukt,
            toleranzProzent: toleranzProzent,
            notizen: notizen,
            createdAt: createdAt,
            updatedAt: updatedAt,
            deletedAt: deletedAt,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String id,
            required String productId,
            required String rawMaterialId,
            required double mengeProKgProdukt,
            Value<double?> toleranzProzent = const Value.absent(),
            Value<String?> notizen = const Value.absent(),
            Value<DateTime> createdAt = const Value.absent(),
            Value<DateTime> updatedAt = const Value.absent(),
            Value<DateTime?> deletedAt = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              ProductRawMaterialsCompanion.insert(
            id: id,
            productId: productId,
            rawMaterialId: rawMaterialId,
            mengeProKgProdukt: mengeProKgProdukt,
            toleranzProzent: toleranzProzent,
            notizen: notizen,
            createdAt: createdAt,
            updatedAt: updatedAt,
            deletedAt: deletedAt,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (
                    e.readTable(table),
                    $$ProductRawMaterialsTableReferences(db, table, e)
                  ))
              .toList(),
          prefetchHooksCallback: ({productId = false, rawMaterialId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins: <
                  T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic>>(state) {
                if (productId) {
                  state = state.withJoin(
                    currentTable: table,
                    currentColumn: table.productId,
                    referencedTable: $$ProductRawMaterialsTableReferences
                        ._productIdTable(db),
                    referencedColumn: $$ProductRawMaterialsTableReferences
                        ._productIdTable(db)
                        .id,
                  ) as T;
                }
                if (rawMaterialId) {
                  state = state.withJoin(
                    currentTable: table,
                    currentColumn: table.rawMaterialId,
                    referencedTable: $$ProductRawMaterialsTableReferences
                        ._rawMaterialIdTable(db),
                    referencedColumn: $$ProductRawMaterialsTableReferences
                        ._rawMaterialIdTable(db)
                        .id,
                  ) as T;
                }

                return state;
              },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ));
}

typedef $$ProductRawMaterialsTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $ProductRawMaterialsTable,
    ProductRawMaterial,
    $$ProductRawMaterialsTableFilterComposer,
    $$ProductRawMaterialsTableOrderingComposer,
    $$ProductRawMaterialsTableAnnotationComposer,
    $$ProductRawMaterialsTableCreateCompanionBuilder,
    $$ProductRawMaterialsTableUpdateCompanionBuilder,
    (ProductRawMaterial, $$ProductRawMaterialsTableReferences),
    ProductRawMaterial,
    PrefetchHooks Function({bool productId, bool rawMaterialId})>;
typedef $$RawMaterialBatchesTableCreateCompanionBuilder
    = RawMaterialBatchesCompanion Function({
  required String id,
  required String rawMaterialId,
  required String chargennummer,
  Value<DateTime?> mhd,
  required DateTime eingangsDatum,
  required double mengeInitial,
  required double mengeAktuell,
  required String einheit,
  Value<String?> lieferant,
  Value<String?> notizen,
  Value<DateTime> createdAt,
  Value<DateTime> updatedAt,
  Value<DateTime?> deletedAt,
  Value<int> rowid,
});
typedef $$RawMaterialBatchesTableUpdateCompanionBuilder
    = RawMaterialBatchesCompanion Function({
  Value<String> id,
  Value<String> rawMaterialId,
  Value<String> chargennummer,
  Value<DateTime?> mhd,
  Value<DateTime> eingangsDatum,
  Value<double> mengeInitial,
  Value<double> mengeAktuell,
  Value<String> einheit,
  Value<String?> lieferant,
  Value<String?> notizen,
  Value<DateTime> createdAt,
  Value<DateTime> updatedAt,
  Value<DateTime?> deletedAt,
  Value<int> rowid,
});

final class $$RawMaterialBatchesTableReferences extends BaseReferences<
    _$AppDatabase, $RawMaterialBatchesTable, RawMaterialBatche> {
  $$RawMaterialBatchesTableReferences(
      super.$_db, super.$_table, super.$_typedResult);

  static $RawMaterialsTable _rawMaterialIdTable(_$AppDatabase db) =>
      db.rawMaterials.createAlias($_aliasNameGenerator(
          db.rawMaterialBatches.rawMaterialId, db.rawMaterials.id));

  $$RawMaterialsTableProcessedTableManager get rawMaterialId {
    final $_column = $_itemColumn<String>('raw_material_id')!;

    final manager = $$RawMaterialsTableTableManager($_db, $_db.rawMaterials)
        .filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_rawMaterialIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
        manager.$state.copyWith(prefetchedData: [item]));
  }
}

class $$RawMaterialBatchesTableFilterComposer
    extends Composer<_$AppDatabase, $RawMaterialBatchesTable> {
  $$RawMaterialBatchesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get chargennummer => $composableBuilder(
      column: $table.chargennummer, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get mhd => $composableBuilder(
      column: $table.mhd, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get eingangsDatum => $composableBuilder(
      column: $table.eingangsDatum, builder: (column) => ColumnFilters(column));

  ColumnFilters<double> get mengeInitial => $composableBuilder(
      column: $table.mengeInitial, builder: (column) => ColumnFilters(column));

  ColumnFilters<double> get mengeAktuell => $composableBuilder(
      column: $table.mengeAktuell, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get einheit => $composableBuilder(
      column: $table.einheit, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get lieferant => $composableBuilder(
      column: $table.lieferant, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get notizen => $composableBuilder(
      column: $table.notizen, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
      column: $table.updatedAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get deletedAt => $composableBuilder(
      column: $table.deletedAt, builder: (column) => ColumnFilters(column));

  $$RawMaterialsTableFilterComposer get rawMaterialId {
    final $$RawMaterialsTableFilterComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.rawMaterialId,
        referencedTable: $db.rawMaterials,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$RawMaterialsTableFilterComposer(
              $db: $db,
              $table: $db.rawMaterials,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }
}

class $$RawMaterialBatchesTableOrderingComposer
    extends Composer<_$AppDatabase, $RawMaterialBatchesTable> {
  $$RawMaterialBatchesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get chargennummer => $composableBuilder(
      column: $table.chargennummer,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get mhd => $composableBuilder(
      column: $table.mhd, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get eingangsDatum => $composableBuilder(
      column: $table.eingangsDatum,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<double> get mengeInitial => $composableBuilder(
      column: $table.mengeInitial,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<double> get mengeAktuell => $composableBuilder(
      column: $table.mengeAktuell,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get einheit => $composableBuilder(
      column: $table.einheit, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get lieferant => $composableBuilder(
      column: $table.lieferant, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get notizen => $composableBuilder(
      column: $table.notizen, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
      column: $table.updatedAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get deletedAt => $composableBuilder(
      column: $table.deletedAt, builder: (column) => ColumnOrderings(column));

  $$RawMaterialsTableOrderingComposer get rawMaterialId {
    final $$RawMaterialsTableOrderingComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.rawMaterialId,
        referencedTable: $db.rawMaterials,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$RawMaterialsTableOrderingComposer(
              $db: $db,
              $table: $db.rawMaterials,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }
}

class $$RawMaterialBatchesTableAnnotationComposer
    extends Composer<_$AppDatabase, $RawMaterialBatchesTable> {
  $$RawMaterialBatchesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get chargennummer => $composableBuilder(
      column: $table.chargennummer, builder: (column) => column);

  GeneratedColumn<DateTime> get mhd =>
      $composableBuilder(column: $table.mhd, builder: (column) => column);

  GeneratedColumn<DateTime> get eingangsDatum => $composableBuilder(
      column: $table.eingangsDatum, builder: (column) => column);

  GeneratedColumn<double> get mengeInitial => $composableBuilder(
      column: $table.mengeInitial, builder: (column) => column);

  GeneratedColumn<double> get mengeAktuell => $composableBuilder(
      column: $table.mengeAktuell, builder: (column) => column);

  GeneratedColumn<String> get einheit =>
      $composableBuilder(column: $table.einheit, builder: (column) => column);

  GeneratedColumn<String> get lieferant =>
      $composableBuilder(column: $table.lieferant, builder: (column) => column);

  GeneratedColumn<String> get notizen =>
      $composableBuilder(column: $table.notizen, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<DateTime> get deletedAt =>
      $composableBuilder(column: $table.deletedAt, builder: (column) => column);

  $$RawMaterialsTableAnnotationComposer get rawMaterialId {
    final $$RawMaterialsTableAnnotationComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.rawMaterialId,
        referencedTable: $db.rawMaterials,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$RawMaterialsTableAnnotationComposer(
              $db: $db,
              $table: $db.rawMaterials,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }
}

class $$RawMaterialBatchesTableTableManager extends RootTableManager<
    _$AppDatabase,
    $RawMaterialBatchesTable,
    RawMaterialBatche,
    $$RawMaterialBatchesTableFilterComposer,
    $$RawMaterialBatchesTableOrderingComposer,
    $$RawMaterialBatchesTableAnnotationComposer,
    $$RawMaterialBatchesTableCreateCompanionBuilder,
    $$RawMaterialBatchesTableUpdateCompanionBuilder,
    (RawMaterialBatche, $$RawMaterialBatchesTableReferences),
    RawMaterialBatche,
    PrefetchHooks Function({bool rawMaterialId})> {
  $$RawMaterialBatchesTableTableManager(
      _$AppDatabase db, $RawMaterialBatchesTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$RawMaterialBatchesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$RawMaterialBatchesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$RawMaterialBatchesTableAnnotationComposer(
                  $db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> id = const Value.absent(),
            Value<String> rawMaterialId = const Value.absent(),
            Value<String> chargennummer = const Value.absent(),
            Value<DateTime?> mhd = const Value.absent(),
            Value<DateTime> eingangsDatum = const Value.absent(),
            Value<double> mengeInitial = const Value.absent(),
            Value<double> mengeAktuell = const Value.absent(),
            Value<String> einheit = const Value.absent(),
            Value<String?> lieferant = const Value.absent(),
            Value<String?> notizen = const Value.absent(),
            Value<DateTime> createdAt = const Value.absent(),
            Value<DateTime> updatedAt = const Value.absent(),
            Value<DateTime?> deletedAt = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              RawMaterialBatchesCompanion(
            id: id,
            rawMaterialId: rawMaterialId,
            chargennummer: chargennummer,
            mhd: mhd,
            eingangsDatum: eingangsDatum,
            mengeInitial: mengeInitial,
            mengeAktuell: mengeAktuell,
            einheit: einheit,
            lieferant: lieferant,
            notizen: notizen,
            createdAt: createdAt,
            updatedAt: updatedAt,
            deletedAt: deletedAt,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String id,
            required String rawMaterialId,
            required String chargennummer,
            Value<DateTime?> mhd = const Value.absent(),
            required DateTime eingangsDatum,
            required double mengeInitial,
            required double mengeAktuell,
            required String einheit,
            Value<String?> lieferant = const Value.absent(),
            Value<String?> notizen = const Value.absent(),
            Value<DateTime> createdAt = const Value.absent(),
            Value<DateTime> updatedAt = const Value.absent(),
            Value<DateTime?> deletedAt = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              RawMaterialBatchesCompanion.insert(
            id: id,
            rawMaterialId: rawMaterialId,
            chargennummer: chargennummer,
            mhd: mhd,
            eingangsDatum: eingangsDatum,
            mengeInitial: mengeInitial,
            mengeAktuell: mengeAktuell,
            einheit: einheit,
            lieferant: lieferant,
            notizen: notizen,
            createdAt: createdAt,
            updatedAt: updatedAt,
            deletedAt: deletedAt,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (
                    e.readTable(table),
                    $$RawMaterialBatchesTableReferences(db, table, e)
                  ))
              .toList(),
          prefetchHooksCallback: ({rawMaterialId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins: <
                  T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic>>(state) {
                if (rawMaterialId) {
                  state = state.withJoin(
                    currentTable: table,
                    currentColumn: table.rawMaterialId,
                    referencedTable: $$RawMaterialBatchesTableReferences
                        ._rawMaterialIdTable(db),
                    referencedColumn: $$RawMaterialBatchesTableReferences
                        ._rawMaterialIdTable(db)
                        .id,
                  ) as T;
                }

                return state;
              },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ));
}

typedef $$RawMaterialBatchesTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $RawMaterialBatchesTable,
    RawMaterialBatche,
    $$RawMaterialBatchesTableFilterComposer,
    $$RawMaterialBatchesTableOrderingComposer,
    $$RawMaterialBatchesTableAnnotationComposer,
    $$RawMaterialBatchesTableCreateCompanionBuilder,
    $$RawMaterialBatchesTableUpdateCompanionBuilder,
    (RawMaterialBatche, $$RawMaterialBatchesTableReferences),
    RawMaterialBatche,
    PrefetchHooks Function({bool rawMaterialId})>;
typedef $$ProductionTasksTableCreateCompanionBuilder = ProductionTasksCompanion
    Function({
  required String id,
  required String productId,
  required double mengeKg,
  required DateTime datum,
  required String abteilung,
  Value<String?> startZeit,
  required double geplanteDauerMinuten,
  required int geplanteMitarbeiter,
  Value<String> status,
  Value<String?> parentTaskId,
  Value<String?> notizen,
  Value<DateTime> createdAt,
  Value<DateTime> updatedAt,
  Value<DateTime?> deletedAt,
  Value<int> rowid,
});
typedef $$ProductionTasksTableUpdateCompanionBuilder = ProductionTasksCompanion
    Function({
  Value<String> id,
  Value<String> productId,
  Value<double> mengeKg,
  Value<DateTime> datum,
  Value<String> abteilung,
  Value<String?> startZeit,
  Value<double> geplanteDauerMinuten,
  Value<int> geplanteMitarbeiter,
  Value<String> status,
  Value<String?> parentTaskId,
  Value<String?> notizen,
  Value<DateTime> createdAt,
  Value<DateTime> updatedAt,
  Value<DateTime?> deletedAt,
  Value<int> rowid,
});

final class $$ProductionTasksTableReferences extends BaseReferences<
    _$AppDatabase, $ProductionTasksTable, ProductionTask> {
  $$ProductionTasksTableReferences(
      super.$_db, super.$_table, super.$_typedResult);

  static $ProductsTable _productIdTable(_$AppDatabase db) =>
      db.products.createAlias(
          $_aliasNameGenerator(db.productionTasks.productId, db.products.id));

  $$ProductsTableProcessedTableManager get productId {
    final $_column = $_itemColumn<String>('product_id')!;

    final manager = $$ProductsTableTableManager($_db, $_db.products)
        .filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_productIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
        manager.$state.copyWith(prefetchedData: [item]));
  }

  static MultiTypedResultKey<$ProductionRunsTable, List<ProductionRun>>
      _productionRunsRefsTable(_$AppDatabase db) =>
          MultiTypedResultKey.fromTable(db.productionRuns,
              aliasName: $_aliasNameGenerator(
                  db.productionTasks.id, db.productionRuns.taskId));

  $$ProductionRunsTableProcessedTableManager get productionRunsRefs {
    final manager = $$ProductionRunsTableTableManager($_db, $_db.productionRuns)
        .filter((f) => f.taskId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_productionRunsRefsTable($_db));
    return ProcessedTableManager(
        manager.$state.copyWith(prefetchedData: cache));
  }
}

class $$ProductionTasksTableFilterComposer
    extends Composer<_$AppDatabase, $ProductionTasksTable> {
  $$ProductionTasksTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<double> get mengeKg => $composableBuilder(
      column: $table.mengeKg, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get datum => $composableBuilder(
      column: $table.datum, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get abteilung => $composableBuilder(
      column: $table.abteilung, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get startZeit => $composableBuilder(
      column: $table.startZeit, builder: (column) => ColumnFilters(column));

  ColumnFilters<double> get geplanteDauerMinuten => $composableBuilder(
      column: $table.geplanteDauerMinuten,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get geplanteMitarbeiter => $composableBuilder(
      column: $table.geplanteMitarbeiter,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get status => $composableBuilder(
      column: $table.status, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get parentTaskId => $composableBuilder(
      column: $table.parentTaskId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get notizen => $composableBuilder(
      column: $table.notizen, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
      column: $table.updatedAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get deletedAt => $composableBuilder(
      column: $table.deletedAt, builder: (column) => ColumnFilters(column));

  $$ProductsTableFilterComposer get productId {
    final $$ProductsTableFilterComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.productId,
        referencedTable: $db.products,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$ProductsTableFilterComposer(
              $db: $db,
              $table: $db.products,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }

  Expression<bool> productionRunsRefs(
      Expression<bool> Function($$ProductionRunsTableFilterComposer f) f) {
    final $$ProductionRunsTableFilterComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.id,
        referencedTable: $db.productionRuns,
        getReferencedColumn: (t) => t.taskId,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$ProductionRunsTableFilterComposer(
              $db: $db,
              $table: $db.productionRuns,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return f(composer);
  }
}

class $$ProductionTasksTableOrderingComposer
    extends Composer<_$AppDatabase, $ProductionTasksTable> {
  $$ProductionTasksTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<double> get mengeKg => $composableBuilder(
      column: $table.mengeKg, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get datum => $composableBuilder(
      column: $table.datum, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get abteilung => $composableBuilder(
      column: $table.abteilung, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get startZeit => $composableBuilder(
      column: $table.startZeit, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<double> get geplanteDauerMinuten => $composableBuilder(
      column: $table.geplanteDauerMinuten,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get geplanteMitarbeiter => $composableBuilder(
      column: $table.geplanteMitarbeiter,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get status => $composableBuilder(
      column: $table.status, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get parentTaskId => $composableBuilder(
      column: $table.parentTaskId,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get notizen => $composableBuilder(
      column: $table.notizen, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
      column: $table.updatedAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get deletedAt => $composableBuilder(
      column: $table.deletedAt, builder: (column) => ColumnOrderings(column));

  $$ProductsTableOrderingComposer get productId {
    final $$ProductsTableOrderingComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.productId,
        referencedTable: $db.products,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$ProductsTableOrderingComposer(
              $db: $db,
              $table: $db.products,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }
}

class $$ProductionTasksTableAnnotationComposer
    extends Composer<_$AppDatabase, $ProductionTasksTable> {
  $$ProductionTasksTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<double> get mengeKg =>
      $composableBuilder(column: $table.mengeKg, builder: (column) => column);

  GeneratedColumn<DateTime> get datum =>
      $composableBuilder(column: $table.datum, builder: (column) => column);

  GeneratedColumn<String> get abteilung =>
      $composableBuilder(column: $table.abteilung, builder: (column) => column);

  GeneratedColumn<String> get startZeit =>
      $composableBuilder(column: $table.startZeit, builder: (column) => column);

  GeneratedColumn<double> get geplanteDauerMinuten => $composableBuilder(
      column: $table.geplanteDauerMinuten, builder: (column) => column);

  GeneratedColumn<int> get geplanteMitarbeiter => $composableBuilder(
      column: $table.geplanteMitarbeiter, builder: (column) => column);

  GeneratedColumn<String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumn<String> get parentTaskId => $composableBuilder(
      column: $table.parentTaskId, builder: (column) => column);

  GeneratedColumn<String> get notizen =>
      $composableBuilder(column: $table.notizen, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<DateTime> get deletedAt =>
      $composableBuilder(column: $table.deletedAt, builder: (column) => column);

  $$ProductsTableAnnotationComposer get productId {
    final $$ProductsTableAnnotationComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.productId,
        referencedTable: $db.products,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$ProductsTableAnnotationComposer(
              $db: $db,
              $table: $db.products,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }

  Expression<T> productionRunsRefs<T extends Object>(
      Expression<T> Function($$ProductionRunsTableAnnotationComposer a) f) {
    final $$ProductionRunsTableAnnotationComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.id,
        referencedTable: $db.productionRuns,
        getReferencedColumn: (t) => t.taskId,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$ProductionRunsTableAnnotationComposer(
              $db: $db,
              $table: $db.productionRuns,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return f(composer);
  }
}

class $$ProductionTasksTableTableManager extends RootTableManager<
    _$AppDatabase,
    $ProductionTasksTable,
    ProductionTask,
    $$ProductionTasksTableFilterComposer,
    $$ProductionTasksTableOrderingComposer,
    $$ProductionTasksTableAnnotationComposer,
    $$ProductionTasksTableCreateCompanionBuilder,
    $$ProductionTasksTableUpdateCompanionBuilder,
    (ProductionTask, $$ProductionTasksTableReferences),
    ProductionTask,
    PrefetchHooks Function({bool productId, bool productionRunsRefs})> {
  $$ProductionTasksTableTableManager(
      _$AppDatabase db, $ProductionTasksTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ProductionTasksTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ProductionTasksTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ProductionTasksTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> id = const Value.absent(),
            Value<String> productId = const Value.absent(),
            Value<double> mengeKg = const Value.absent(),
            Value<DateTime> datum = const Value.absent(),
            Value<String> abteilung = const Value.absent(),
            Value<String?> startZeit = const Value.absent(),
            Value<double> geplanteDauerMinuten = const Value.absent(),
            Value<int> geplanteMitarbeiter = const Value.absent(),
            Value<String> status = const Value.absent(),
            Value<String?> parentTaskId = const Value.absent(),
            Value<String?> notizen = const Value.absent(),
            Value<DateTime> createdAt = const Value.absent(),
            Value<DateTime> updatedAt = const Value.absent(),
            Value<DateTime?> deletedAt = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              ProductionTasksCompanion(
            id: id,
            productId: productId,
            mengeKg: mengeKg,
            datum: datum,
            abteilung: abteilung,
            startZeit: startZeit,
            geplanteDauerMinuten: geplanteDauerMinuten,
            geplanteMitarbeiter: geplanteMitarbeiter,
            status: status,
            parentTaskId: parentTaskId,
            notizen: notizen,
            createdAt: createdAt,
            updatedAt: updatedAt,
            deletedAt: deletedAt,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String id,
            required String productId,
            required double mengeKg,
            required DateTime datum,
            required String abteilung,
            Value<String?> startZeit = const Value.absent(),
            required double geplanteDauerMinuten,
            required int geplanteMitarbeiter,
            Value<String> status = const Value.absent(),
            Value<String?> parentTaskId = const Value.absent(),
            Value<String?> notizen = const Value.absent(),
            Value<DateTime> createdAt = const Value.absent(),
            Value<DateTime> updatedAt = const Value.absent(),
            Value<DateTime?> deletedAt = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              ProductionTasksCompanion.insert(
            id: id,
            productId: productId,
            mengeKg: mengeKg,
            datum: datum,
            abteilung: abteilung,
            startZeit: startZeit,
            geplanteDauerMinuten: geplanteDauerMinuten,
            geplanteMitarbeiter: geplanteMitarbeiter,
            status: status,
            parentTaskId: parentTaskId,
            notizen: notizen,
            createdAt: createdAt,
            updatedAt: updatedAt,
            deletedAt: deletedAt,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (
                    e.readTable(table),
                    $$ProductionTasksTableReferences(db, table, e)
                  ))
              .toList(),
          prefetchHooksCallback: (
              {productId = false, productionRunsRefs = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [
                if (productionRunsRefs) db.productionRuns
              ],
              addJoins: <
                  T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic>>(state) {
                if (productId) {
                  state = state.withJoin(
                    currentTable: table,
                    currentColumn: table.productId,
                    referencedTable:
                        $$ProductionTasksTableReferences._productIdTable(db),
                    referencedColumn:
                        $$ProductionTasksTableReferences._productIdTable(db).id,
                  ) as T;
                }

                return state;
              },
              getPrefetchedDataCallback: (items) async {
                return [
                  if (productionRunsRefs)
                    await $_getPrefetchedData<ProductionTask,
                            $ProductionTasksTable, ProductionRun>(
                        currentTable: table,
                        referencedTable: $$ProductionTasksTableReferences
                            ._productionRunsRefsTable(db),
                        managerFromTypedResult: (p0) =>
                            $$ProductionTasksTableReferences(db, table, p0)
                                .productionRunsRefs,
                        referencedItemsForCurrentItem: (item,
                                referencedItems) =>
                            referencedItems.where((e) => e.taskId == item.id),
                        typedResults: items)
                ];
              },
            );
          },
        ));
}

typedef $$ProductionTasksTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $ProductionTasksTable,
    ProductionTask,
    $$ProductionTasksTableFilterComposer,
    $$ProductionTasksTableOrderingComposer,
    $$ProductionTasksTableAnnotationComposer,
    $$ProductionTasksTableCreateCompanionBuilder,
    $$ProductionTasksTableUpdateCompanionBuilder,
    (ProductionTask, $$ProductionTasksTableReferences),
    ProductionTask,
    PrefetchHooks Function({bool productId, bool productionRunsRefs})>;
typedef $$ProductionRunsTableCreateCompanionBuilder = ProductionRunsCompanion
    Function({
  required String id,
  required String taskId,
  required double tatsaechlicheDauerMinuten,
  required int tatsaechlicheMitarbeiter,
  required double tatsaechlicheMengeKg,
  Value<String?> verwendeteChargenJson,
  Value<String?> notizen,
  Value<String?> erfasstVon,
  Value<DateTime> erfasstAm,
  Value<DateTime> createdAt,
  Value<DateTime> updatedAt,
  Value<DateTime?> deletedAt,
  Value<int> rowid,
});
typedef $$ProductionRunsTableUpdateCompanionBuilder = ProductionRunsCompanion
    Function({
  Value<String> id,
  Value<String> taskId,
  Value<double> tatsaechlicheDauerMinuten,
  Value<int> tatsaechlicheMitarbeiter,
  Value<double> tatsaechlicheMengeKg,
  Value<String?> verwendeteChargenJson,
  Value<String?> notizen,
  Value<String?> erfasstVon,
  Value<DateTime> erfasstAm,
  Value<DateTime> createdAt,
  Value<DateTime> updatedAt,
  Value<DateTime?> deletedAt,
  Value<int> rowid,
});

final class $$ProductionRunsTableReferences
    extends BaseReferences<_$AppDatabase, $ProductionRunsTable, ProductionRun> {
  $$ProductionRunsTableReferences(
      super.$_db, super.$_table, super.$_typedResult);

  static $ProductionTasksTable _taskIdTable(_$AppDatabase db) =>
      db.productionTasks.createAlias($_aliasNameGenerator(
          db.productionRuns.taskId, db.productionTasks.id));

  $$ProductionTasksTableProcessedTableManager get taskId {
    final $_column = $_itemColumn<String>('task_id')!;

    final manager =
        $$ProductionTasksTableTableManager($_db, $_db.productionTasks)
            .filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_taskIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
        manager.$state.copyWith(prefetchedData: [item]));
  }
}

class $$ProductionRunsTableFilterComposer
    extends Composer<_$AppDatabase, $ProductionRunsTable> {
  $$ProductionRunsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<double> get tatsaechlicheDauerMinuten => $composableBuilder(
      column: $table.tatsaechlicheDauerMinuten,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get tatsaechlicheMitarbeiter => $composableBuilder(
      column: $table.tatsaechlicheMitarbeiter,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<double> get tatsaechlicheMengeKg => $composableBuilder(
      column: $table.tatsaechlicheMengeKg,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get verwendeteChargenJson => $composableBuilder(
      column: $table.verwendeteChargenJson,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get notizen => $composableBuilder(
      column: $table.notizen, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get erfasstVon => $composableBuilder(
      column: $table.erfasstVon, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get erfasstAm => $composableBuilder(
      column: $table.erfasstAm, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
      column: $table.updatedAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get deletedAt => $composableBuilder(
      column: $table.deletedAt, builder: (column) => ColumnFilters(column));

  $$ProductionTasksTableFilterComposer get taskId {
    final $$ProductionTasksTableFilterComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.taskId,
        referencedTable: $db.productionTasks,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$ProductionTasksTableFilterComposer(
              $db: $db,
              $table: $db.productionTasks,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }
}

class $$ProductionRunsTableOrderingComposer
    extends Composer<_$AppDatabase, $ProductionRunsTable> {
  $$ProductionRunsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<double> get tatsaechlicheDauerMinuten => $composableBuilder(
      column: $table.tatsaechlicheDauerMinuten,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get tatsaechlicheMitarbeiter => $composableBuilder(
      column: $table.tatsaechlicheMitarbeiter,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<double> get tatsaechlicheMengeKg => $composableBuilder(
      column: $table.tatsaechlicheMengeKg,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get verwendeteChargenJson => $composableBuilder(
      column: $table.verwendeteChargenJson,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get notizen => $composableBuilder(
      column: $table.notizen, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get erfasstVon => $composableBuilder(
      column: $table.erfasstVon, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get erfasstAm => $composableBuilder(
      column: $table.erfasstAm, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
      column: $table.updatedAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get deletedAt => $composableBuilder(
      column: $table.deletedAt, builder: (column) => ColumnOrderings(column));

  $$ProductionTasksTableOrderingComposer get taskId {
    final $$ProductionTasksTableOrderingComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.taskId,
        referencedTable: $db.productionTasks,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$ProductionTasksTableOrderingComposer(
              $db: $db,
              $table: $db.productionTasks,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }
}

class $$ProductionRunsTableAnnotationComposer
    extends Composer<_$AppDatabase, $ProductionRunsTable> {
  $$ProductionRunsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<double> get tatsaechlicheDauerMinuten => $composableBuilder(
      column: $table.tatsaechlicheDauerMinuten, builder: (column) => column);

  GeneratedColumn<int> get tatsaechlicheMitarbeiter => $composableBuilder(
      column: $table.tatsaechlicheMitarbeiter, builder: (column) => column);

  GeneratedColumn<double> get tatsaechlicheMengeKg => $composableBuilder(
      column: $table.tatsaechlicheMengeKg, builder: (column) => column);

  GeneratedColumn<String> get verwendeteChargenJson => $composableBuilder(
      column: $table.verwendeteChargenJson, builder: (column) => column);

  GeneratedColumn<String> get notizen =>
      $composableBuilder(column: $table.notizen, builder: (column) => column);

  GeneratedColumn<String> get erfasstVon => $composableBuilder(
      column: $table.erfasstVon, builder: (column) => column);

  GeneratedColumn<DateTime> get erfasstAm =>
      $composableBuilder(column: $table.erfasstAm, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<DateTime> get deletedAt =>
      $composableBuilder(column: $table.deletedAt, builder: (column) => column);

  $$ProductionTasksTableAnnotationComposer get taskId {
    final $$ProductionTasksTableAnnotationComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.taskId,
        referencedTable: $db.productionTasks,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$ProductionTasksTableAnnotationComposer(
              $db: $db,
              $table: $db.productionTasks,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }
}

class $$ProductionRunsTableTableManager extends RootTableManager<
    _$AppDatabase,
    $ProductionRunsTable,
    ProductionRun,
    $$ProductionRunsTableFilterComposer,
    $$ProductionRunsTableOrderingComposer,
    $$ProductionRunsTableAnnotationComposer,
    $$ProductionRunsTableCreateCompanionBuilder,
    $$ProductionRunsTableUpdateCompanionBuilder,
    (ProductionRun, $$ProductionRunsTableReferences),
    ProductionRun,
    PrefetchHooks Function({bool taskId})> {
  $$ProductionRunsTableTableManager(
      _$AppDatabase db, $ProductionRunsTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ProductionRunsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ProductionRunsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ProductionRunsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> id = const Value.absent(),
            Value<String> taskId = const Value.absent(),
            Value<double> tatsaechlicheDauerMinuten = const Value.absent(),
            Value<int> tatsaechlicheMitarbeiter = const Value.absent(),
            Value<double> tatsaechlicheMengeKg = const Value.absent(),
            Value<String?> verwendeteChargenJson = const Value.absent(),
            Value<String?> notizen = const Value.absent(),
            Value<String?> erfasstVon = const Value.absent(),
            Value<DateTime> erfasstAm = const Value.absent(),
            Value<DateTime> createdAt = const Value.absent(),
            Value<DateTime> updatedAt = const Value.absent(),
            Value<DateTime?> deletedAt = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              ProductionRunsCompanion(
            id: id,
            taskId: taskId,
            tatsaechlicheDauerMinuten: tatsaechlicheDauerMinuten,
            tatsaechlicheMitarbeiter: tatsaechlicheMitarbeiter,
            tatsaechlicheMengeKg: tatsaechlicheMengeKg,
            verwendeteChargenJson: verwendeteChargenJson,
            notizen: notizen,
            erfasstVon: erfasstVon,
            erfasstAm: erfasstAm,
            createdAt: createdAt,
            updatedAt: updatedAt,
            deletedAt: deletedAt,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String id,
            required String taskId,
            required double tatsaechlicheDauerMinuten,
            required int tatsaechlicheMitarbeiter,
            required double tatsaechlicheMengeKg,
            Value<String?> verwendeteChargenJson = const Value.absent(),
            Value<String?> notizen = const Value.absent(),
            Value<String?> erfasstVon = const Value.absent(),
            Value<DateTime> erfasstAm = const Value.absent(),
            Value<DateTime> createdAt = const Value.absent(),
            Value<DateTime> updatedAt = const Value.absent(),
            Value<DateTime?> deletedAt = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              ProductionRunsCompanion.insert(
            id: id,
            taskId: taskId,
            tatsaechlicheDauerMinuten: tatsaechlicheDauerMinuten,
            tatsaechlicheMitarbeiter: tatsaechlicheMitarbeiter,
            tatsaechlicheMengeKg: tatsaechlicheMengeKg,
            verwendeteChargenJson: verwendeteChargenJson,
            notizen: notizen,
            erfasstVon: erfasstVon,
            erfasstAm: erfasstAm,
            createdAt: createdAt,
            updatedAt: updatedAt,
            deletedAt: deletedAt,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (
                    e.readTable(table),
                    $$ProductionRunsTableReferences(db, table, e)
                  ))
              .toList(),
          prefetchHooksCallback: ({taskId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins: <
                  T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic>>(state) {
                if (taskId) {
                  state = state.withJoin(
                    currentTable: table,
                    currentColumn: table.taskId,
                    referencedTable:
                        $$ProductionRunsTableReferences._taskIdTable(db),
                    referencedColumn:
                        $$ProductionRunsTableReferences._taskIdTable(db).id,
                  ) as T;
                }

                return state;
              },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ));
}

typedef $$ProductionRunsTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $ProductionRunsTable,
    ProductionRun,
    $$ProductionRunsTableFilterComposer,
    $$ProductionRunsTableOrderingComposer,
    $$ProductionRunsTableAnnotationComposer,
    $$ProductionRunsTableCreateCompanionBuilder,
    $$ProductionRunsTableUpdateCompanionBuilder,
    (ProductionRun, $$ProductionRunsTableReferences),
    ProductionRun,
    PrefetchHooks Function({bool taskId})>;
typedef $$TaskDependenciesTableCreateCompanionBuilder
    = TaskDependenciesCompanion Function({
  required String id,
  required String fromTaskId,
  required String toTaskId,
  Value<String> typ,
  Value<DateTime> createdAt,
  Value<DateTime> updatedAt,
  Value<DateTime?> deletedAt,
  Value<int> rowid,
});
typedef $$TaskDependenciesTableUpdateCompanionBuilder
    = TaskDependenciesCompanion Function({
  Value<String> id,
  Value<String> fromTaskId,
  Value<String> toTaskId,
  Value<String> typ,
  Value<DateTime> createdAt,
  Value<DateTime> updatedAt,
  Value<DateTime?> deletedAt,
  Value<int> rowid,
});

final class $$TaskDependenciesTableReferences extends BaseReferences<
    _$AppDatabase, $TaskDependenciesTable, TaskDependency> {
  $$TaskDependenciesTableReferences(
      super.$_db, super.$_table, super.$_typedResult);

  static $ProductionTasksTable _fromTaskIdTable(_$AppDatabase db) =>
      db.productionTasks.createAlias($_aliasNameGenerator(
          db.taskDependencies.fromTaskId, db.productionTasks.id));

  $$ProductionTasksTableProcessedTableManager get fromTaskId {
    final $_column = $_itemColumn<String>('from_task_id')!;

    final manager =
        $$ProductionTasksTableTableManager($_db, $_db.productionTasks)
            .filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_fromTaskIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
        manager.$state.copyWith(prefetchedData: [item]));
  }

  static $ProductionTasksTable _toTaskIdTable(_$AppDatabase db) =>
      db.productionTasks.createAlias($_aliasNameGenerator(
          db.taskDependencies.toTaskId, db.productionTasks.id));

  $$ProductionTasksTableProcessedTableManager get toTaskId {
    final $_column = $_itemColumn<String>('to_task_id')!;

    final manager =
        $$ProductionTasksTableTableManager($_db, $_db.productionTasks)
            .filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_toTaskIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
        manager.$state.copyWith(prefetchedData: [item]));
  }
}

class $$TaskDependenciesTableFilterComposer
    extends Composer<_$AppDatabase, $TaskDependenciesTable> {
  $$TaskDependenciesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get typ => $composableBuilder(
      column: $table.typ, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
      column: $table.updatedAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get deletedAt => $composableBuilder(
      column: $table.deletedAt, builder: (column) => ColumnFilters(column));

  $$ProductionTasksTableFilterComposer get fromTaskId {
    final $$ProductionTasksTableFilterComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.fromTaskId,
        referencedTable: $db.productionTasks,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$ProductionTasksTableFilterComposer(
              $db: $db,
              $table: $db.productionTasks,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }

  $$ProductionTasksTableFilterComposer get toTaskId {
    final $$ProductionTasksTableFilterComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.toTaskId,
        referencedTable: $db.productionTasks,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$ProductionTasksTableFilterComposer(
              $db: $db,
              $table: $db.productionTasks,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }
}

class $$TaskDependenciesTableOrderingComposer
    extends Composer<_$AppDatabase, $TaskDependenciesTable> {
  $$TaskDependenciesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get typ => $composableBuilder(
      column: $table.typ, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
      column: $table.updatedAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get deletedAt => $composableBuilder(
      column: $table.deletedAt, builder: (column) => ColumnOrderings(column));

  $$ProductionTasksTableOrderingComposer get fromTaskId {
    final $$ProductionTasksTableOrderingComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.fromTaskId,
        referencedTable: $db.productionTasks,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$ProductionTasksTableOrderingComposer(
              $db: $db,
              $table: $db.productionTasks,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }

  $$ProductionTasksTableOrderingComposer get toTaskId {
    final $$ProductionTasksTableOrderingComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.toTaskId,
        referencedTable: $db.productionTasks,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$ProductionTasksTableOrderingComposer(
              $db: $db,
              $table: $db.productionTasks,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }
}

class $$TaskDependenciesTableAnnotationComposer
    extends Composer<_$AppDatabase, $TaskDependenciesTable> {
  $$TaskDependenciesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get typ =>
      $composableBuilder(column: $table.typ, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<DateTime> get deletedAt =>
      $composableBuilder(column: $table.deletedAt, builder: (column) => column);

  $$ProductionTasksTableAnnotationComposer get fromTaskId {
    final $$ProductionTasksTableAnnotationComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.fromTaskId,
        referencedTable: $db.productionTasks,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$ProductionTasksTableAnnotationComposer(
              $db: $db,
              $table: $db.productionTasks,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }

  $$ProductionTasksTableAnnotationComposer get toTaskId {
    final $$ProductionTasksTableAnnotationComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.toTaskId,
        referencedTable: $db.productionTasks,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$ProductionTasksTableAnnotationComposer(
              $db: $db,
              $table: $db.productionTasks,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }
}

class $$TaskDependenciesTableTableManager extends RootTableManager<
    _$AppDatabase,
    $TaskDependenciesTable,
    TaskDependency,
    $$TaskDependenciesTableFilterComposer,
    $$TaskDependenciesTableOrderingComposer,
    $$TaskDependenciesTableAnnotationComposer,
    $$TaskDependenciesTableCreateCompanionBuilder,
    $$TaskDependenciesTableUpdateCompanionBuilder,
    (TaskDependency, $$TaskDependenciesTableReferences),
    TaskDependency,
    PrefetchHooks Function({bool fromTaskId, bool toTaskId})> {
  $$TaskDependenciesTableTableManager(
      _$AppDatabase db, $TaskDependenciesTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$TaskDependenciesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$TaskDependenciesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$TaskDependenciesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> id = const Value.absent(),
            Value<String> fromTaskId = const Value.absent(),
            Value<String> toTaskId = const Value.absent(),
            Value<String> typ = const Value.absent(),
            Value<DateTime> createdAt = const Value.absent(),
            Value<DateTime> updatedAt = const Value.absent(),
            Value<DateTime?> deletedAt = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              TaskDependenciesCompanion(
            id: id,
            fromTaskId: fromTaskId,
            toTaskId: toTaskId,
            typ: typ,
            createdAt: createdAt,
            updatedAt: updatedAt,
            deletedAt: deletedAt,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String id,
            required String fromTaskId,
            required String toTaskId,
            Value<String> typ = const Value.absent(),
            Value<DateTime> createdAt = const Value.absent(),
            Value<DateTime> updatedAt = const Value.absent(),
            Value<DateTime?> deletedAt = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              TaskDependenciesCompanion.insert(
            id: id,
            fromTaskId: fromTaskId,
            toTaskId: toTaskId,
            typ: typ,
            createdAt: createdAt,
            updatedAt: updatedAt,
            deletedAt: deletedAt,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (
                    e.readTable(table),
                    $$TaskDependenciesTableReferences(db, table, e)
                  ))
              .toList(),
          prefetchHooksCallback: ({fromTaskId = false, toTaskId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins: <
                  T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic>>(state) {
                if (fromTaskId) {
                  state = state.withJoin(
                    currentTable: table,
                    currentColumn: table.fromTaskId,
                    referencedTable:
                        $$TaskDependenciesTableReferences._fromTaskIdTable(db),
                    referencedColumn: $$TaskDependenciesTableReferences
                        ._fromTaskIdTable(db)
                        .id,
                  ) as T;
                }
                if (toTaskId) {
                  state = state.withJoin(
                    currentTable: table,
                    currentColumn: table.toTaskId,
                    referencedTable:
                        $$TaskDependenciesTableReferences._toTaskIdTable(db),
                    referencedColumn:
                        $$TaskDependenciesTableReferences._toTaskIdTable(db).id,
                  ) as T;
                }

                return state;
              },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ));
}

typedef $$TaskDependenciesTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $TaskDependenciesTable,
    TaskDependency,
    $$TaskDependenciesTableFilterComposer,
    $$TaskDependenciesTableOrderingComposer,
    $$TaskDependenciesTableAnnotationComposer,
    $$TaskDependenciesTableCreateCompanionBuilder,
    $$TaskDependenciesTableUpdateCompanionBuilder,
    (TaskDependency, $$TaskDependenciesTableReferences),
    TaskDependency,
    PrefetchHooks Function({bool fromTaskId, bool toTaskId})>;
typedef $$OrderListItemsTableCreateCompanionBuilder = OrderListItemsCompanion
    Function({
  required String id,
  required String rawMaterialId,
  required DateTime wocheStartDatum,
  required double benoetigteMenge,
  required String einheit,
  Value<bool> bestellt,
  Value<DateTime?> bestelltAm,
  Value<bool> geliefert,
  Value<DateTime?> geliefertAm,
  Value<String?> notizen,
  Value<DateTime> createdAt,
  Value<DateTime> updatedAt,
  Value<DateTime?> deletedAt,
  Value<int> rowid,
});
typedef $$OrderListItemsTableUpdateCompanionBuilder = OrderListItemsCompanion
    Function({
  Value<String> id,
  Value<String> rawMaterialId,
  Value<DateTime> wocheStartDatum,
  Value<double> benoetigteMenge,
  Value<String> einheit,
  Value<bool> bestellt,
  Value<DateTime?> bestelltAm,
  Value<bool> geliefert,
  Value<DateTime?> geliefertAm,
  Value<String?> notizen,
  Value<DateTime> createdAt,
  Value<DateTime> updatedAt,
  Value<DateTime?> deletedAt,
  Value<int> rowid,
});

final class $$OrderListItemsTableReferences
    extends BaseReferences<_$AppDatabase, $OrderListItemsTable, OrderListItem> {
  $$OrderListItemsTableReferences(
      super.$_db, super.$_table, super.$_typedResult);

  static $RawMaterialsTable _rawMaterialIdTable(_$AppDatabase db) =>
      db.rawMaterials.createAlias($_aliasNameGenerator(
          db.orderListItems.rawMaterialId, db.rawMaterials.id));

  $$RawMaterialsTableProcessedTableManager get rawMaterialId {
    final $_column = $_itemColumn<String>('raw_material_id')!;

    final manager = $$RawMaterialsTableTableManager($_db, $_db.rawMaterials)
        .filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_rawMaterialIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
        manager.$state.copyWith(prefetchedData: [item]));
  }
}

class $$OrderListItemsTableFilterComposer
    extends Composer<_$AppDatabase, $OrderListItemsTable> {
  $$OrderListItemsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get wocheStartDatum => $composableBuilder(
      column: $table.wocheStartDatum,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<double> get benoetigteMenge => $composableBuilder(
      column: $table.benoetigteMenge,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get einheit => $composableBuilder(
      column: $table.einheit, builder: (column) => ColumnFilters(column));

  ColumnFilters<bool> get bestellt => $composableBuilder(
      column: $table.bestellt, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get bestelltAm => $composableBuilder(
      column: $table.bestelltAm, builder: (column) => ColumnFilters(column));

  ColumnFilters<bool> get geliefert => $composableBuilder(
      column: $table.geliefert, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get geliefertAm => $composableBuilder(
      column: $table.geliefertAm, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get notizen => $composableBuilder(
      column: $table.notizen, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
      column: $table.updatedAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get deletedAt => $composableBuilder(
      column: $table.deletedAt, builder: (column) => ColumnFilters(column));

  $$RawMaterialsTableFilterComposer get rawMaterialId {
    final $$RawMaterialsTableFilterComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.rawMaterialId,
        referencedTable: $db.rawMaterials,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$RawMaterialsTableFilterComposer(
              $db: $db,
              $table: $db.rawMaterials,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }
}

class $$OrderListItemsTableOrderingComposer
    extends Composer<_$AppDatabase, $OrderListItemsTable> {
  $$OrderListItemsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get wocheStartDatum => $composableBuilder(
      column: $table.wocheStartDatum,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<double> get benoetigteMenge => $composableBuilder(
      column: $table.benoetigteMenge,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get einheit => $composableBuilder(
      column: $table.einheit, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<bool> get bestellt => $composableBuilder(
      column: $table.bestellt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get bestelltAm => $composableBuilder(
      column: $table.bestelltAm, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<bool> get geliefert => $composableBuilder(
      column: $table.geliefert, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get geliefertAm => $composableBuilder(
      column: $table.geliefertAm, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get notizen => $composableBuilder(
      column: $table.notizen, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
      column: $table.updatedAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get deletedAt => $composableBuilder(
      column: $table.deletedAt, builder: (column) => ColumnOrderings(column));

  $$RawMaterialsTableOrderingComposer get rawMaterialId {
    final $$RawMaterialsTableOrderingComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.rawMaterialId,
        referencedTable: $db.rawMaterials,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$RawMaterialsTableOrderingComposer(
              $db: $db,
              $table: $db.rawMaterials,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }
}

class $$OrderListItemsTableAnnotationComposer
    extends Composer<_$AppDatabase, $OrderListItemsTable> {
  $$OrderListItemsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<DateTime> get wocheStartDatum => $composableBuilder(
      column: $table.wocheStartDatum, builder: (column) => column);

  GeneratedColumn<double> get benoetigteMenge => $composableBuilder(
      column: $table.benoetigteMenge, builder: (column) => column);

  GeneratedColumn<String> get einheit =>
      $composableBuilder(column: $table.einheit, builder: (column) => column);

  GeneratedColumn<bool> get bestellt =>
      $composableBuilder(column: $table.bestellt, builder: (column) => column);

  GeneratedColumn<DateTime> get bestelltAm => $composableBuilder(
      column: $table.bestelltAm, builder: (column) => column);

  GeneratedColumn<bool> get geliefert =>
      $composableBuilder(column: $table.geliefert, builder: (column) => column);

  GeneratedColumn<DateTime> get geliefertAm => $composableBuilder(
      column: $table.geliefertAm, builder: (column) => column);

  GeneratedColumn<String> get notizen =>
      $composableBuilder(column: $table.notizen, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<DateTime> get deletedAt =>
      $composableBuilder(column: $table.deletedAt, builder: (column) => column);

  $$RawMaterialsTableAnnotationComposer get rawMaterialId {
    final $$RawMaterialsTableAnnotationComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.rawMaterialId,
        referencedTable: $db.rawMaterials,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$RawMaterialsTableAnnotationComposer(
              $db: $db,
              $table: $db.rawMaterials,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }
}

class $$OrderListItemsTableTableManager extends RootTableManager<
    _$AppDatabase,
    $OrderListItemsTable,
    OrderListItem,
    $$OrderListItemsTableFilterComposer,
    $$OrderListItemsTableOrderingComposer,
    $$OrderListItemsTableAnnotationComposer,
    $$OrderListItemsTableCreateCompanionBuilder,
    $$OrderListItemsTableUpdateCompanionBuilder,
    (OrderListItem, $$OrderListItemsTableReferences),
    OrderListItem,
    PrefetchHooks Function({bool rawMaterialId})> {
  $$OrderListItemsTableTableManager(
      _$AppDatabase db, $OrderListItemsTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$OrderListItemsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$OrderListItemsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$OrderListItemsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> id = const Value.absent(),
            Value<String> rawMaterialId = const Value.absent(),
            Value<DateTime> wocheStartDatum = const Value.absent(),
            Value<double> benoetigteMenge = const Value.absent(),
            Value<String> einheit = const Value.absent(),
            Value<bool> bestellt = const Value.absent(),
            Value<DateTime?> bestelltAm = const Value.absent(),
            Value<bool> geliefert = const Value.absent(),
            Value<DateTime?> geliefertAm = const Value.absent(),
            Value<String?> notizen = const Value.absent(),
            Value<DateTime> createdAt = const Value.absent(),
            Value<DateTime> updatedAt = const Value.absent(),
            Value<DateTime?> deletedAt = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              OrderListItemsCompanion(
            id: id,
            rawMaterialId: rawMaterialId,
            wocheStartDatum: wocheStartDatum,
            benoetigteMenge: benoetigteMenge,
            einheit: einheit,
            bestellt: bestellt,
            bestelltAm: bestelltAm,
            geliefert: geliefert,
            geliefertAm: geliefertAm,
            notizen: notizen,
            createdAt: createdAt,
            updatedAt: updatedAt,
            deletedAt: deletedAt,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String id,
            required String rawMaterialId,
            required DateTime wocheStartDatum,
            required double benoetigteMenge,
            required String einheit,
            Value<bool> bestellt = const Value.absent(),
            Value<DateTime?> bestelltAm = const Value.absent(),
            Value<bool> geliefert = const Value.absent(),
            Value<DateTime?> geliefertAm = const Value.absent(),
            Value<String?> notizen = const Value.absent(),
            Value<DateTime> createdAt = const Value.absent(),
            Value<DateTime> updatedAt = const Value.absent(),
            Value<DateTime?> deletedAt = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              OrderListItemsCompanion.insert(
            id: id,
            rawMaterialId: rawMaterialId,
            wocheStartDatum: wocheStartDatum,
            benoetigteMenge: benoetigteMenge,
            einheit: einheit,
            bestellt: bestellt,
            bestelltAm: bestelltAm,
            geliefert: geliefert,
            geliefertAm: geliefertAm,
            notizen: notizen,
            createdAt: createdAt,
            updatedAt: updatedAt,
            deletedAt: deletedAt,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (
                    e.readTable(table),
                    $$OrderListItemsTableReferences(db, table, e)
                  ))
              .toList(),
          prefetchHooksCallback: ({rawMaterialId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins: <
                  T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic>>(state) {
                if (rawMaterialId) {
                  state = state.withJoin(
                    currentTable: table,
                    currentColumn: table.rawMaterialId,
                    referencedTable:
                        $$OrderListItemsTableReferences._rawMaterialIdTable(db),
                    referencedColumn: $$OrderListItemsTableReferences
                        ._rawMaterialIdTable(db)
                        .id,
                  ) as T;
                }

                return state;
              },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ));
}

typedef $$OrderListItemsTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $OrderListItemsTable,
    OrderListItem,
    $$OrderListItemsTableFilterComposer,
    $$OrderListItemsTableOrderingComposer,
    $$OrderListItemsTableAnnotationComposer,
    $$OrderListItemsTableCreateCompanionBuilder,
    $$OrderListItemsTableUpdateCompanionBuilder,
    (OrderListItem, $$OrderListItemsTableReferences),
    OrderListItem,
    PrefetchHooks Function({bool rawMaterialId})>;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$ProductsTableTableManager get products =>
      $$ProductsTableTableManager(_db, _db.products);
  $$ProductStepsTableTableManager get productSteps =>
      $$ProductStepsTableTableManager(_db, _db.productSteps);
  $$RawMaterialsTableTableManager get rawMaterials =>
      $$RawMaterialsTableTableManager(_db, _db.rawMaterials);
  $$ProductRawMaterialsTableTableManager get productRawMaterials =>
      $$ProductRawMaterialsTableTableManager(_db, _db.productRawMaterials);
  $$RawMaterialBatchesTableTableManager get rawMaterialBatches =>
      $$RawMaterialBatchesTableTableManager(_db, _db.rawMaterialBatches);
  $$ProductionTasksTableTableManager get productionTasks =>
      $$ProductionTasksTableTableManager(_db, _db.productionTasks);
  $$ProductionRunsTableTableManager get productionRuns =>
      $$ProductionRunsTableTableManager(_db, _db.productionRuns);
  $$TaskDependenciesTableTableManager get taskDependencies =>
      $$TaskDependenciesTableTableManager(_db, _db.taskDependencies);
  $$OrderListItemsTableTableManager get orderListItems =>
      $$OrderListItemsTableTableManager(_db, _db.orderListItems);
}
