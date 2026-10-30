# Restricted Russian CA

[English](#english) | [Русский](#russian)

Ansible playbooks for building a local **Restricted Russian CA**, cross-signing the supplied Russian Trusted Root CA public key, and installing the resulting chain on macOS and Windows.

Плейбуки Ansible для создания собственного **Restricted Russian CA**, перекрёстного подписания публичного ключа Russian Trusted Root CA и установки полученной цепочки на macOS и Windows.

> **Never publish `generated/ca.key`, backups of it, or private-key containers.**
>
> **Никогда не публикуйте `generated/ca.key`, его резервные копии или контейнеры с закрытым ключом.**

## Source files and Windows example / Исходные файлы и пример для Windows

```text
restricted-russian-ca/
├── README.md
├── .gitignore
├── .gitattributes
├── build-ca.yml
├── install-keychain.yml
├── remove-keychain.yml
├── build-windows-certs.yml
├── pack-windows-certs.yml
├── domains.txt
├── Install-Certificates.cmd
├── Remove-Certificates-All.cmd
├── Russian_Trusted_Root_CA.cer
├── Russian_Trusted_Sub_CA.cer
├── Russian_Trusted_Sub_CA_2024.cer
└── Restricted-Russian-CA-Windows.zip
```

`generated/` and `windows/` are local build directories and must not be committed. The three original `.cer` files are public CA certificates, not private keys. `Restricted-Russian-CA-Windows.zip` can be published at the repository root after checking its contents: four public certificates and two CMD scripts, without a private key.

`generated/` и `windows/` — локальные каталоги сборки, которые не нужно добавлять в Git. Три исходных `.cer` — публичные сертификаты УЦ, не закрытые ключи. `Restricted-Russian-CA-Windows.zip` можно разместить в корне репозитория после проверки его состава: четыре публичных сертификата и два CMD-скрипта, без закрытого ключа.

<a id="english"></a>

## English

### 1. Trust model and limitations

The intended validation path is:

```text
Website certificate
  → Russian Trusted Sub CA
  → Russian Trusted Root CA (cross-signed, generated/new_root_ca.crt)
  → Restricted Russian CA (trusted anchor, generated/ca.crt)
```

The project does not reissue website certificates. It creates an alternative CA chain using the Russian root's existing public key. The local root contains a critical DNS `nameConstraints` extension generated from `domains.txt`.

Only **Restricted Russian CA** must be explicitly trusted. Import the cross-signed Russian root and Sub CAs as intermediates, not as independent trust anchors. Do not install the original `Russian_Trusted_Root_CA.cer` as a trusted root: that creates an alternative path around the restrictions.

**Why avoid unrestricted trust in RU CA.** Installing the original Russian root CA without constraints extends trust beyond the websites you actually need. Certificate misissuance, malicious issuance or compromised CA keys can enable website impersonation and HTTPS interception when an attacker can intercept the connection. Installing a CA does not itself decrypt traffic. This risk applies to any unrestricted CA; the project therefore limits trust to selected DNS zones. [3](#ref-3), [7](#ref-7)

The restrictions apply to DNS names when this chain is used; other certificates may still validate through other trusted CAs. Restrictions on other name types are not configured here.

Client handling of constraints on a trust anchor must be tested: a successful import or one working website is not sufficient. Test both an allowed and a disallowed DNS name issued under the same PKI. Do not disable TLS verification. [3](#ref-3), [4](#ref-4)

### 2. Install macOS prerequisites

Default playbook paths target Apple Silicon with Homebrew in `/opt/homebrew`. In these playbooks, administrator privileges are needed for Keychain installation and removal.

Install Apple's Command Line Tools if missing, and complete the installation dialog before continuing:

```bash
xcode-select --install
```

Install Homebrew if it is not already installed, using its official installer: [1](#ref-1)

```bash
/bin/bash -c "$(/usr/bin/curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

Follow the installer's **Next steps** to persist Homebrew's `shellenv` in your shell profile. For the current Apple Silicon terminal session:

```bash
eval "$(/opt/homebrew/bin/brew shellenv)"
```

Install the required packages: [2](#ref-2)

```bash
brew update
brew install openssl@3 ansible git
```

Publishing through the GitLab web interface and Git does not require a separate GitLab CLI.

Check the installed tools:

```bash
ansible-playbook --version
"$(brew --prefix openssl@3)/bin/openssl" version
command -v /usr/bin/zip /usr/bin/unzip
```

On an Intel Mac or with a different Homebrew prefix, edit `openssl_bin` in the `vars` section of each certificate playbook, or pass the actual path when running it:

```bash
ansible-playbook build-ca.yml \
  -e "openssl_bin=$(brew --prefix openssl@3)/bin/openssl"
```

Use the same option with `install-keychain.yml`, `remove-keychain.yml` and `build-windows-certs.yml`. `pack-windows-certs.yml` does not use OpenSSL. The project does not pin tool versions; record the versions used for your build.

Build and export operations can be adapted to other systems with Ansible and OpenSSL by configuring the appropriate tool paths. This does not apply to Keychain installation and removal: those two playbooks are macOS-only. Packaging also requires `zip`, `unzip` and Bash.

### 3. Obtain the sources and edit domains

After the repository has been published, replace `REPOSITORY_URL` below with its HTTPS clone URL from GitLab:

```bash
git clone REPOSITORY_URL restricted-russian-ca
cd restricted-russian-ca
nano domains.txt
```

For an already installed configuration, keep using the existing project directory and preserve `generated/`. A fresh clone has no private key: building there creates a new local CA.

Use one DNS constraint per line. Empty lines and lines starting with `#` are ignored. Use ASCII DNS names, or Punycode for internationalized domains, without a URL scheme, port, path or `*.` wildcard. Put comments on separate lines.

| Entry | Meaning in this configuration |
| --- | --- |
| `sberbank.ru` | The domain itself and all its subdomains |
| `.sberbank.ru` | Subdomains only, excluding `sberbank.ru` itself |
| `orgp.spb.ru` | The domain and its subdomains; not an exact-host-only rule |

All DNS SANs in a certificate must satisfy the constraints, not just the hostname being opened. For example, a certificate containing both `sberbank.ru` and `sbrf.ru` requires both zones to be permitted. Expand the scope of trust deliberately. [3](#ref-3)

The current [domains.txt](domains.txt) contains **13 DNS zones**. Every entry below permits the domain itself and its subdomains:

```text
alfabank.ru
vtb.ru
rshb.ru
bspb.ru
sberbank.ru
sbrf.ru
tkbbank.ru
mkb.ru
absolutbank.ru
domrfbank.ru
energotransbank.com
orgp.spb.ru
rzd.ru
```

This list describes the source configuration. Before publishing the Windows example package, check that its certificate constraints match the list: editing `domains.txt` does not automatically update an existing ZIP.

The current `domains.txt` supports permitted DNS entries only; it does not implement an exclusion syntax for an exact-host-only rule. Editing the file alone does not change installed certificates. For an already installed CA, follow [section 5](#en-update-domains) before rebuilding.

### 4. Build and install on macOS for the first time

Verify that the three source `.cer` files are present. Run the build as your normal user:

```bash
ansible-playbook build-ca.yml
```

Inspect the generated certificates before trusting them:

```bash
OPENSSL="$(brew --prefix openssl@3)/bin/openssl"

"$OPENSSL" x509 -in generated/ca.crt \
  -noout -subject -issuer -fingerprint -sha256 -ext nameConstraints

"$OPENSSL" x509 -in generated/new_root_ca.crt \
  -noout -subject -issuer
```

The first certificate should have Subject and Issuer `CN=Restricted Russian CA`; the cross-signed certificate should have Issuer `CN=Restricted Russian CA`.

Install into `/Library/Keychains/System.keychain`:

```bash
ansible-playbook -K install-keychain.yml
```

`-K` requests your administrator password for Ansible's privilege escalation. The playbook explicitly trusts only the local root and imports the other three certificates without independent trust settings. Certificate presence is checked by fingerprint.

Restart the browser and test both allowed and disallowed sites. A successful installation does not by itself prove that the intended restrictions are enforced.

<a id="en-update-domains"></a>

### 5. Change domains or remove the macOS certificates

**Remove the installed version before `build-ca.yml` overwrites the files used to identify it.** Removal targets fingerprints from the current `generated/`; it does not automatically clean up all previous roots.

```bash
ansible-playbook -K remove-keychain.yml
```

After successful removal, edit the domain list, generate new certificates and install them:

```bash
nano domains.txt
ansible-playbook build-ca.yml &&
ansible-playbook -K install-keychain.yml
```

To prepare the Windows certificates and package them into `Restricted-Russian-CA-Windows.zip`, run:

```bash
ansible-playbook build-windows-certs.yml &&
ansible-playbook pack-windows-certs.yml
```

To remove only the currently identifiable macOS chain:

```bash
ansible-playbook -K remove-keychain.yml
```

Keep `generated/` until removal is complete. The playbook operates on the System Keychain, not on every user's keychains or management profiles.

If you have already rebuilt before removing the old version, the current files may no longer identify the installed certificates. Use the preserved old certificate files or verified old fingerprints for removal.

<a id="en-windows-package"></a>

### 6. Export and package for Windows

Ready-made Windows example: [Restricted-Russian-CA-Windows.zip](Restricted-Russian-CA-Windows.zip).

It should use the DNS zones from the current `domains.txt`, listed in section 3. **Installing the example means trusting the holder of this build's private key.** Building your own CA keeps its private key under your control. Before installation, check the root fingerprint and constraints; the scheme must be tested in the client you use.

On the Mac:

```bash
ansible-playbook build-windows-certs.yml &&
ansible-playbook pack-windows-certs.yml

unzip -l Restricted-Russian-CA-Windows.zip
```

`build-windows-certs.yml` converts four certificates from `generated/` to DER `.cer` files in `windows/`. `pack-windows-certs.yml` copies the two CMD scripts from the project root and uses `zip -j` to create a flat archive:

```text
Restricted-Russian-CA-Windows.zip
├── Restricted-Russian-CA.cer
├── Russian-Trusted-Root-cross-signed.cer
├── Russian-Trusted-Sub-CA.cer
├── Russian-Trusted-Sub-CA-2024.cer
├── Install-Certificates.cmd
└── Remove-Certificates-All.cmd
```

There is no `windows/` directory prefix inside the archive.

The private key and original self-signed Russian root are not included. Transfer the package to your devices over a trusted channel; independently verify the local root's fingerprint before importing it. Other users should preferably build their own CA rather than trust someone else's root.

### 7. Install and remove on Windows

Extract all six files into one directory, for example `C:\RuCert`. Open **Command Prompt as Administrator**:

```cmd
cd /d C:\RuCert
Install-Certificates.cmd
```

The installer uses `certutil` and the following stores: [5](#ref-5)

| Store | Certificate |
| --- | --- |
| `LocalMachine\Root` | `Restricted-Russian-CA.cer` |
| `LocalMachine\CA` | Cross-signed Russian root and both Sub CAs |

Check the store contents:

```cmd
certutil -store Root "Restricted Russian CA"
certutil -store CA "Russian Trusted Root CA"
certutil -store CA "Russian Trusted Sub CA"
```

Restart Chrome/Edge, test allowed and disallowed sites, and inspect the certification path. A successful import does not prove that the client enforces root constraints. The installer does not remove older certificates or roll back a partially completed import.

Check the stores without changing certificates:

```cmd
Remove-Certificates-All.cmd /check
```

To remove certificates, run the following command and confirm with `Y`:

```cmd
Remove-Certificates-All.cmd
```

**Warning: Windows removal is broad cleanup, not deletion limited to the current four files.** The script targets matching `Restricted Russian CA`, `Russian Trusted Root CA` and `Russian Trusted Sub CA` certificates, including older versions and the **original Russian root**, in `Root` and `CA` for the computer and the current account.

This can affect other applications. Other users are not covered; management policies may restore certificates.

`/check` does not change certificate stores but writes logs to a temporary directory. A name match may also occur in an issuer field: review the logs rather than treating every match as an independently trusted root.

When updating, first run `/check`, deliberately remove the old certificates, then run `Install-Certificates.cmd` from the newly extracted package. Windows does not need Ansible, OpenSSL or the CA private key.

### 8. Source behavior and repository security

The current `build-ca.yml` is not a full CA lifecycle manager: normalized certificates and the public key are reused if already present.

For a complete rebuild, first remove the installed chain while the old files are still in `generated/`. Keep a protected backup if needed, then remove `generated/` and build again.

**Removing this directory also removes `ca.key`: the next build creates a new private key and a new CA**, which must be installed again on every device using it.

`build-windows-certs.yml` rewrites DER files and reports `changed` on every export. In `pack-windows-certs.yml --check`, CMD copying is previewed and ZIP creation is skipped.

Never publish `generated/`, `windows/`, private keys or their backups. One explicit exception is made for the ready-made example: `Restricted-Russian-CA-Windows.zip` is published at the repository root after checking its contents and CA constraints.

`.gitignore` does not remove already tracked files or secrets from Git history. If a CA private key has been published, treat it as compromised and replace the CA on the devices that trust it. [6](#ref-6)

<a id="russian"></a>

## Русский

### 1. Модель доверия и ограничения

Предполагаемая цепочка проверки:

```text
Сертификат сайта
  → Russian Trusted Sub CA
  → Russian Trusted Root CA (cross-signed, generated/new_root_ca.crt)
  → Restricted Russian CA (доверенный корень, generated/ca.crt)
```

Проект не перевыпускает сертификаты сайтов. Он создаёт альтернативную цепочку УЦ с существующим публичным ключом российского корня. В собственный корень включается критическое расширение DNS `nameConstraints` из `domains.txt`.

Явно доверять нужно только **Restricted Russian CA**. Cross-signed российский корень и Sub CA используются как промежуточные сертификаты, без самостоятельного доверия. Не устанавливайте оригинальный `Russian_Trusted_Root_CA.cer` как доверенный корень: это создаст путь в обход ограничений.

**Почему не стоит безусловно доверять RU CA.** Установка оригинального российского корневого CA без ограничений расширяет доверие не только на нужные сайты. Ошибочная или злонамеренная выдача сертификата, а также компрометация ключей УЦ могут позволить подменить другой сайт и перехватить HTTPS-трафик при наличии доступа к каналу связи. Сама установка CA не расшифровывает трафик. Этот риск свойствен любому неограниченному CA; поэтому проект ограничивает область доверия выбранными DNS-зонами. [3](#ref-3), [7](#ref-7)

Ограничения относятся к DNS-именам при использовании данной цепочки; остальные сертификаты могут проверяться через другие доверенные УЦ. Ограничения других типов имён здесь не настраиваются.

Поддержку ограничений доверенного корня необходимо проверить в каждом клиенте: успешного импорта или открытия одного сайта недостаточно. Нужны положительный и отрицательный тесты для одной PKI. Не отключайте проверку TLS. [3](#ref-3), [4](#ref-4)

### 2. Установка компонентов на Mac

В исходниках по умолчанию заданы пути Apple Silicon с Homebrew в `/opt/homebrew`. В этих плейбуках права администратора нужны для установки и удаления в Keychain.

Если Command Line Tools отсутствуют, выполните команду и завершите установку через появившийся диалог:

```bash
xcode-select --install
```

Если Homebrew ещё не установлен, используйте официальный установщик: [1](#ref-1)

```bash
/bin/bash -c "$(/usr/bin/curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

Выполните **Next steps**, которые напечатает установщик, чтобы сохранить `shellenv` в профиле вашей оболочки. Для текущего сеанса Terminal на Apple Silicon:

```bash
eval "$(/opt/homebrew/bin/brew shellenv)"
```

Установите необходимые пакеты: [2](#ref-2)

```bash
brew update
brew install openssl@3 ansible git
```

Для публикации через веб-интерфейс GitLab и Git отдельная CLI-программа GitLab не требуется.

Проверьте установленные инструменты:

```bash
ansible-playbook --version
"$(brew --prefix openssl@3)/bin/openssl" version
command -v /usr/bin/zip /usr/bin/unzip
```

На Intel Mac или при другом расположении Homebrew отредактируйте `openssl_bin` в разделе `vars` каждого плейбука, работающего с сертификатами, либо передавайте фактический путь при запуске:

```bash
ansible-playbook build-ca.yml \
  -e "openssl_bin=$(brew --prefix openssl@3)/bin/openssl"
```

Такой же параметр нужен для `install-keychain.yml`, `remove-keychain.yml` и `build-windows-certs.yml`. Упаковщик `pack-windows-certs.yml` OpenSSL не использует. Версии инструментов проект не фиксирует; сохраните сведения о версиях, с которыми выполнялась ваша сборка.

Операции сборки и экспорта можно адаптировать к другим системам с Ansible и OpenSSL, настроив соответствующие пути к инструментам. Это не относится к установке и удалению в Keychain: эти два плейбука работают только на macOS. Для упаковки также нужны `zip`, `unzip` и Bash.

### 3. Получение исходников и список доменов

После публикации репозитория замените `REPOSITORY_URL` ниже его HTTPS-адресом клонирования из GitLab:

```bash
git clone REPOSITORY_URL restricted-russian-ca
cd restricted-russian-ca
nano domains.txt
```

Для уже установленной конфигурации продолжайте работу в существующем каталоге проекта, сохраняя `generated/`. В новом клоне закрытого ключа нет: сборка создаст новый собственный CA.

Одна строка — одно DNS-ограничение. Пустые строки и строки, начинающиеся с `#`, пропускаются. Указывайте ASCII DNS-имена, для национальных доменов — Punycode; без `https://`, порта, пути и шаблона `*.`. Комментарии размещайте на отдельных строках.

| Запись | Значение в этой конфигурации |
| --- | --- |
| `sberbank.ru` | Сам домен и любые его поддомены |
| `.sberbank.ru` | Только поддомены, без самого `sberbank.ru` |
| `orgp.spb.ru` | Домен и его поддомены; это не правило «только точное имя» |

Ограничения проверяются по всем DNS-именам SAN сертификата, а не только по открываемому адресу. Например, сертификату одновременно с `sberbank.ru` и `sbrf.ru` нужны разрешения для обеих зон. Расширяйте область доверия осознанно. [3](#ref-3)

Текущий список в [domains.txt](domains.txt) — **13 DNS-зон**. Все записи ниже разрешают сам домен и его поддомены:

```text
alfabank.ru
vtb.ru
rshb.ru
bspb.ru
sberbank.ru
sbrf.ru
tkbbank.ru
mkb.ru
absolutbank.ru
domrfbank.ru
energotransbank.com
orgp.spb.ru
rzd.ru
```

Этот список описывает исходную конфигурацию. Перед публикацией готового Windows-пакета проверьте, что ограничения в его сертификате соответствуют этому списку: изменение `domains.txt` не обновляет существующий ZIP автоматически.

Текущий `domains.txt` поддерживает только разрешённые DNS-записи, без синтаксиса исключений для точного имени. Редактирование файла само по себе не меняет установленные сертификаты. Если CA уже установлен, перед пересборкой используйте порядок из [раздела 5](#ru-update-domains).

### 4. Первая сборка и установка на macOS

Убедитесь в наличии трёх исходных `.cer`. Запускайте сборку от своего пользователя:

```bash
ansible-playbook build-ca.yml
```

Проверьте получившиеся сертификаты перед установкой доверия:

```bash
OPENSSL="$(brew --prefix openssl@3)/bin/openssl"

"$OPENSSL" x509 -in generated/ca.crt \
  -noout -subject -issuer -fingerprint -sha256 -ext nameConstraints

"$OPENSSL" x509 -in generated/new_root_ca.crt \
  -noout -subject -issuer
```

У первого сертификата Subject и Issuer должны быть `CN=Restricted Russian CA`; у cross-signed сертификата Issuer — `CN=Restricted Russian CA`.

Установка в `/Library/Keychains/System.keychain`:

```bash
ansible-playbook -K install-keychain.yml
```

`-K` запрашивает пароль администратора для повышения привилегий Ansible. Плейбук явно доверяет только собственному корню, остальные три сертификата импортируются без самостоятельного доверия. Наличие сертификатов проверяется по отпечаткам.

Перезапустите браузер и проверьте разрешённые и неразрешённые сайты. Успешная установка сама по себе не доказывает применение нужных ограничений.

<a id="ru-update-domains"></a>

### 5. Изменение доменов и удаление на Mac

**Удаляйте установленную версию до того, как `build-ca.yml` перезапишет файлы для её идентификации.** Удаление привязано к отпечаткам текущего `generated/`; это не автоматическая очистка всех прежних версий корня.

```bash
ansible-playbook -K remove-keychain.yml
```

После успешного удаления отредактируйте список доменов, создайте новые сертификаты и установите их:

```bash
nano domains.txt
ansible-playbook build-ca.yml &&
ansible-playbook -K install-keychain.yml
```

Для подготовки сертификатов для Windows и упаковки их в архив `Restricted-Russian-CA-Windows.zip` выполните:

```bash
ansible-playbook build-windows-certs.yml &&
ansible-playbook pack-windows-certs.yml
```

Чтобы только удалить текущую идентифицируемую цепочку из macOS:

```bash
ansible-playbook -K remove-keychain.yml
```

Не удаляйте `generated/` до завершения удаления. Плейбук работает с System Keychain, а не со всеми пользовательскими связками ключей или профилями управления.

Если пересборка уже выполнена до удаления старой версии, текущие файлы могут больше не соответствовать установленным сертификатам. Для удаления используйте сохранённые прежние сертификаты или их проверенные отпечатки.

<a id="ru-windows-package"></a>

### 6. Экспорт и ZIP для Windows

Готовый пример для Windows: [Restricted-Russian-CA-Windows.zip](Restricted-Russian-CA-Windows.zip).

В нём должны использоваться DNS-зоны из текущего `domains.txt`, приведённые в разделе 3. **Установка готового примера означает доверие владельцу закрытого ключа этой сборки.** Самостоятельная сборка позволяет оставить закрытый ключ под своим контролем. Перед установкой сверьте отпечаток корня и его ограничения; схема требует проверки в используемом клиенте.

На Mac:

```bash
ansible-playbook build-windows-certs.yml &&
ansible-playbook pack-windows-certs.yml

unzip -l Restricted-Russian-CA-Windows.zip
```

`build-windows-certs.yml` преобразует четыре сертификата из `generated/` в DER `.cer` внутри `windows/`. `pack-windows-certs.yml` копирует два CMD из корня проекта и создаёт через `zip -j` плоский архив:

```text
Restricted-Russian-CA-Windows.zip
├── Restricted-Russian-CA.cer
├── Russian-Trusted-Root-cross-signed.cer
├── Russian-Trusted-Sub-CA.cer
├── Russian-Trusted-Sub-CA-2024.cer
├── Install-Certificates.cmd
└── Remove-Certificates-All.cmd
```

Пути `windows/` внутри архива нет.

Закрытый ключ и оригинальный самоподписанный российский корень в пакет не входят. Передавайте пакет на свои устройства доверенным способом; перед импортом независимо сверьте отпечаток собственного корня. Другим пользователям предпочтительно собирать свой CA, а не устанавливать чужой корень доверия.

### 7. Установка и удаление на Windows

Полностью распакуйте все шесть файлов в один каталог, например `C:\RuCert`. Откройте **CMD от имени администратора**:

```cmd
cd /d C:\RuCert
Install-Certificates.cmd
```

Установщик использует `certutil` и следующие хранилища: [5](#ref-5)

| Хранилище | Сертификат |
| --- | --- |
| `LocalMachine\Root` | `Restricted-Russian-CA.cer` |
| `LocalMachine\CA` | Cross-signed российский корень и оба Sub CA |

Проверка содержимого:

```cmd
certutil -store Root "Restricted Russian CA"
certutil -store CA "Russian Trusted Root CA"
certutil -store CA "Russian Trusted Sub CA"
```

Перезапустите Chrome/Edge, проверьте разрешённые и неразрешённые сайты и цепочку доверия. Успешный импорт не доказывает применение ограничений корня клиентом. Установщик не удаляет старые сертификаты и не откатывает частично завершённый импорт.

Проверка хранилищ без изменения сертификатов:

```cmd
Remove-Certificates-All.cmd /check
```

Для удаления выполните следующую команду и подтвердите действие клавишей `Y`:

```cmd
Remove-Certificates-All.cmd
```

**Внимание: для Windows это широкая очистка, а не удаление только текущих четырёх файлов.** Скрипт обрабатывает совпадающие `Restricted Russian CA`, `Russian Trusted Root CA` и `Russian Trusted Sub CA`, включая прежние версии и **оригинальный российский корень**, в `Root` и `CA` компьютера и текущей учётной записи.

Это может повлиять на другие приложения. Другие пользователи не охватываются; политики управления могут восстановить сертификаты.

`/check` не меняет хранилища, но создаёт журналы во временном каталоге. Совпадение имени возможно и в поле издателя: изучайте журнал, не считая любое совпадение отдельно доверенным корнем.

При обновлении сначала выполните `/check`, осознанно удалите прежние сертификаты, затем запустите `Install-Certificates.cmd` из нового распакованного пакета. Ansible, OpenSSL и закрытый ключ CA на Windows не требуются.

### 8. Особенности исходников и безопасность репозитория

Текущий `build-ca.yml` не является полноценной системой управления жизненным циклом CA: нормализованные сертификаты и публичный ключ повторно используются, если они уже есть.

Для полного перевыпуска сначала удалите установленную цепочку, пока прежние файлы ещё находятся в `generated/`. При необходимости сохраните защищённую резервную копию, затем удалите каталог `generated/` и выполните сборку заново.

**Удаление этого каталога удаляет и `ca.key`: следующая сборка создаст новый закрытый ключ и новый CA**, который потребуется заново установить на всех использующих его устройствах.

`build-windows-certs.yml` перезаписывает DER и сообщает `changed` при каждом экспорте. В `pack-windows-certs.yml --check` копирование CMD проверяется, создание ZIP пропускается.

Не публикуйте `generated/`, `windows/`, закрытые ключи и их резервные копии. Для готового примера сделано одно явное исключение: `Restricted-Russian-CA-Windows.zip` размещается в корне репозитория после проверки его состава и ограничений CA.

`.gitignore` не удаляет уже отслеживаемые файлы или секреты из истории Git. Если закрытый ключ CA был опубликован, считайте его скомпрометированным и замените CA на доверяющих ему устройствах. [6](#ref-6)

## References / Источники

Descriptions of playbook and CMD behavior refer to the source files in this repository. External references cover prerequisites, certificate validation and tooling; they do not replace testing the restrictions in a specific client.

Описание поведения плейбуков и CMD основано на исходниках репозитория. Внешние ссылки относятся к компонентам, проверке сертификатов и инструментам; они не заменяют испытания ограничений в конкретном клиенте.

1. <a id="ref-1"></a> [Homebrew installer](https://brew.sh/) and [installation documentation](https://docs.brew.sh/Installation).
2. <a id="ref-2"></a> Homebrew formulae: [OpenSSL 3](https://formulae.brew.sh/formula/openssl@3), [Ansible](https://formulae.brew.sh/formula/ansible), [Git](https://formulae.brew.sh/formula/git).
3. <a id="ref-3"></a> [RFC 5280 — Name Constraints](https://www.rfc-editor.org/rfc/rfc5280.html#section-4.2.1.10), [OpenSSL DNS name matching](https://raw.githubusercontent.com/openssl/openssl/master/crypto/x509/v3_ncons.c), [OpenSSL extension configuration](https://docs.openssl.org/3.6/man5/x509v3_config/).
4. <a id="ref-4"></a> [OpenSSL verification options](https://docs.openssl.org/3.6/man1/openssl-verification-options/).
5. <a id="ref-5"></a> [Microsoft certutil reference](https://learn.microsoft.com/en-us/windows-server/administration/windows-commands/certutil).
6. <a id="ref-6"></a> [Git ignore rules](https://git-scm.com/docs/gitignore) and [Git attributes](https://git-scm.com/docs/gitattributes).
7. <a id="ref-7"></a> Habr — [«Сертификаты Минцифры — как им не доверять»](https://habr.com/ru/articles/1071256/) (in Russian / на русском). Background on restricting trust in the Russian CA / Обоснование ограничения доверия к российскому УЦ.
