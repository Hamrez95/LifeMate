from pathlib import Path
import runpy

ROOT = Path(__file__).resolve().parents[2]


def replace_once(path: str, old: str, new: str) -> None:
    target = ROOT / path
    text = target.read_text(encoding='utf-8')
    if old not in text:
        if new in text:
            return
        raise SystemExit(f'Expected CareMate diagnostic snippet not found in {path}')
    target.write_text(text.replace(old, new, 1), encoding='utf-8')


replace_once(
    'caremate/lib/main.dart',
    """    } catch (error, stackTrace) {
      debugPrint('Supabase initialization failed: $error\\n$stackTrace');
    }
""",
    """    } catch (_) {
      debugPrint('Supabase initialization failed.');
    }
""",
)
replace_once(
    'caremate/lib/main.dart',
    """  } catch (error, stackTrace) {
    debugPrint(
      'CareMate notification initialization failed: $error\\n$stackTrace',
    );
  }
""",
    """  } catch (_) {
    debugPrint('CareMate notification initialization failed.');
  }
""",
)
replace_once(
    'caremate/lib/screens/dashboard_screen.dart',
    """    } catch (error) {
      debugPrint('CareMate refresh failed: $error');
      _setError('اطلاعات مراقبت دریافت نشد. اتصال اینترنت را بررسی کنید.');
""",
    """    } catch (_) {
      debugPrint('CareMate refresh failed.');
      _setError('اطلاعات مراقبت دریافت نشد. اتصال اینترنت را بررسی کنید.');
""",
)
replace_once(
    'caremate/lib/screens/dashboard_screen.dart',
    """      } catch (error) {
        debugPrint('CareMate notification patient sync failed: $error');
      }
""",
    """      } catch (_) {
        debugPrint('CareMate notification patient sync failed.');
      }
""",
)
replace_once(
    'caremate/lib/screens/dashboard_screen.dart',
    """    } catch (error) {
      debugPrint('CareMate patient switch failed: $error');
      _setError('وضعیت بیمار دریافت نشد.');
""",
    """    } catch (_) {
      debugPrint('CareMate patient switch failed.');
      _setError('وضعیت بیمار دریافت نشد.');
""",
)

for path in (
    ROOT / 'caremate/lib/main.dart',
    ROOT / 'caremate/lib/screens/dashboard_screen.dart',
):
    text = path.read_text(encoding='utf-8')
    if ': $error' in text or '$stackTrace' in text:
        raise SystemExit(f'Unredacted CareMate diagnostic remains in {path}')

runpy.run_path(
    str(ROOT / 'tools/hotfix/enable_internal_device_qa_build.py'),
    run_name='__main__',
)

print('CareMate diagnostic details redacted from startup and patient flows.')
