import 'package:i_can_code/views/base/screen_view_model_base.dart';
import 'package:i_can_code/views/components/vm/vm_session_view_model.dart';
import 'package:mobx/mobx.dart';

part 'tkinter_screen_view_model.g.dart';

class TkinterScreenViewModel = TkinterScreenViewModelBase with _$TkinterScreenViewModel;

abstract class TkinterScreenViewModelBase extends ScreenViewModelBase with Store {

  /// What the editor holds the first time: a window with a label and a button
  /// that counts its clicks. Dutch, like the course it sits beside.
  static const String sample = '''
import tkinter as tk

klikken = 0


def klik():
    global klikken
    klikken = klikken + 1
    label.config(text=f"Je hebt {klikken} keer geklikt")


root = tk.Tk()
root.title("Mijn eerste venster")

label = tk.Label(root, text="Klik op de knop", padx=40, pady=20)
label.pack()

knop = tk.Button(root, text="Klik mij", command=klik)
knop.pack(pady=(0, 20))

root.mainloop()
''';

  /// The machine and the editor whose program it runs, opened on [sample].
  final VmSessionViewModel machine;

  TkinterScreenViewModelBase({required super.contextAccessor, required String subjectSlug})
    : machine = VmSessionViewModel(contextAccessor: contextAccessor, subjectSlug: subjectSlug, program: sample);

  /// The subject this page belongs to. Empty when the address
  /// named something that is not a subject of ours.
  String get subject => machine.subject;

  /// The page `CodeDraftStore` keeps this page's program under.
  String get draftPage => 'tkinter.$subject';

  @override
  void dispose() {
    machine.dispose();
    super.dispose();
  }

}
