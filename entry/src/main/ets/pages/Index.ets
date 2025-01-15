import { worker } from '@kit.ArkTS';
import { resourceManager } from '@kit.LocalizationKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';
import { KeyboardAvoidMode } from '@ohos.arkui.UIContext'
import { BusinessError, request } from '@kit.BasicServicesKit';
import promptAction from '@ohos.promptAction'

interface Message {
    /**
     * 当前支持以下： user: 表示用户 assistant: 表示对话助手
     */
    role: 'user' | 'assistant';

    /**
     * 对话内容，不能为空
     */
    content: string;
}

@Entry
@Component
struct Index {
    private model_list: string[] = [ "Llama-3.2-1B", "SmallThinker-0.5B", "SmallThinker-3B" ];
    private model_options: SelectOption[] = this.model_list.map(item => ({ value: item } as SelectOption));
    @State current_model: string     = ""
    prev_model: string = ""

    private model_base_url = this.getResourceString($r('app.string.huggingface_url'))
    private model_url_map  = new Map([
        ["Llama-3.2-1B",        "PowerServe/Llama-3.2-1B-PowerServe-QNN29-8G4"],
        ["SmallThinker-0.5B",   "PowerServe/SmallThinker-0.5B-PowerServe-QNN29-8G4"],
        ["SmallThinker-3B",     "PowerServe/SmallThinker-3B-PowerServe-QNN29-8G4"]
    ]);

    @State jsWorkerInPutStr: string = '';
    @State status: "Idle" | "Load" | "Infer" = "Idle";
    @State messages: Message[] = [];
    @State latest_message: Message = { role: "assistant", content: this.getResourceString($r("app.string.welcome_words")) }
    @State num_download_task: number = 0;

    myWorker: worker.ThreadWorker = new worker.ThreadWorker("entry/ets/model/Worker.ts");
    private sandboxFilesDir: string = getContext(this).filesDir;

    getResourceString(src: Resource) {
        return getContext(this).resourceManager.getStringSync(src) as string
    }

    build() {
        Column() {

            List() {
                ForEach(this.messages, (_message: Message, index: number) => {
                    ListItem() {
                        if (this.messages[index].role === 'user') {
                            Row() {
                                Text(this.messages[index].content)
                                    .backgroundColor('#ff99c6d2')
                                    .border(
                                        {
                                            radius: 10
                                        }
                                    )
                                    .padding('5%')
                                    .margin({ left: '10%', right: '5%', top: '5%', bottom: '5%' })
                            }
                            .justifyContent(FlexAlign.End)
                            .width('95%')
                        } else {
                            Text(this.messages[index].content)
                                .backgroundColor('#ffb3a7f1')
                                .border(
                                    {
                                        radius: 10
                                    }
                                )
                                .padding('5%')
                                .margin({ left: '5%', right: '10%', top: '5%', bottom: '5%' })
                        }
                    }
                })

                ListItem() {
                    Text(this.latest_message.content)
                        .backgroundColor('#ffb3a7f1')
                        .border(
                            {
                                radius: 10
                            }
                        )
                        .padding('5%')
                        .margin('5%')
                }

            }
            .edgeEffect(EdgeEffect.None)
            .height(`calc(100% - 150vp)`)
            .expandSafeArea([SafeAreaType.KEYBOARD])

            Blank()

            RowSplit().height('20vp')

            Column() {
                GridRow({
                    columns: 8,
                    gutter: { x: 12, y: 12 },
                    breakpoints: { value: ["340vp", "480vp"] },
                    direction: GridRowDirection.Row
                }) {
                    GridCol({ span: 3, offset: 0 }) {
                        Text(`${this.getResourceString($r('app.string.status'))}: ${this.getStatusString(this.status)}`)
                            .width("100%")
                            .height("40vp")
                            .fontFamily("HarmonyHeiTi-Medium")
                            .fontSize("16fp")
                            .fontColor("#ff7cb2ee")
                            .fontWeight(500)
                            .backgroundColor('#61b8b4b4')
                            .borderRadius('25vp')
                            .padding({ left: '14vp'})
                    }
                    GridCol({ span: 5, offset: 0 }) {
                        Select(this.model_options)
                            .value($$this.current_model)
                            .selected(0)
                            .width("100%")
                            .height("40vp")
                            .accessibilityTextHint(this.getResourceString($r("app.string.model")))
                            .onSelect(async (_index: number, value: string) => {
                                if (this.num_download_task != 0) {
                                    promptAction.showToast({
                                        message: `${this.prev_model} ${this.getResourceString($r("app.string.warn_download_model"))}`
                                    });
                                    this.current_model = this.prev_model
                                    return;
                                }

                                this.prev_model = this.current_model
                                // Download model files into sandbox dir
                                const modelDir = `${this.sandboxFilesDir}/${this.prev_model}`
                                if (!fs.accessSync(modelDir)) {
                                    fs.mkdirSync(modelDir)
                                }
                                await this.downloadFile2Sandbox(value, `model.json`)
                                await this.downloadFile2Sandbox(value, `vocab.gguf`)
                                await this.downloadFile2Sandbox(value, `ggml/weights.gguf`)
                            })
                    }
                }
                .height("40vp")
                .width("90%")

                RowSplit().height('20vp')

                GridRow({
                    columns: 5,
                    gutter: { x: 12, y: 12 },
                    breakpoints: { value: ["360vp", "480vp"] },
                    direction: GridRowDirection.Row
                }) {
                    GridCol({ span: 3, offset: 0 }) {
                        TextInput({ text: this.jsWorkerInPutStr })
                            .id("jsWorkerInPutTextArea")
                            .width("100%")
                            .height("40vp")
                            .textAlign(TextAlign.Start)
                            .maxLines(5)
                            .fontFamily("HarmonyHeiTi")
                            .fontSize("16fp")
                            .fontColor("#182431")
                            .fontWeight(400)
                            .borderRadius("15vp")
                            .backgroundColor("#ffc6c6c6")
                            .enableKeyboardOnFocus(true)
                            .onChange((value: string) => {
                                this.jsWorkerInPutStr = value;
                            })
                            .onSubmit(this.inference)
                            .onClick(() => {
                                const windowStage = AppStorage.get('windowStage') as window.WindowStage;
                                windowStage?.getMainWindowSync().getUIContext().setKeyboardAvoidMode(KeyboardAvoidMode.RESIZE);
                            })
                            .enableKeyboardOnFocus(this.num_download_task == 0)
                    }

                    GridCol({ span: 1, offset: 0 }) {
                        Button() {
                            Image($r('app.media.send'))
                                .width("50%")
                                .height("22")
                        }
                        .width("100%")
                        .height("40vp")
                        .borderRadius("20vp")
                        .backgroundColor("#ff4988ca")
                        .onClick(this.inference)
                    }
                    GridCol({ span: 1, offset: 0 }) {
                        Button() {
                            Image($r('app.media.clear'))
                                .width("50%")
                                .height("22")
                        }
                        .width("100%")
                        .height("40vp")
                        .borderRadius("20vp")
                        .backgroundColor("#ff6c834b")
                        .onClick(() => {
                            if (this.status != "Idle") {
                                promptAction.showToast({
                                    message: this.getResourceString($r("app.string.warn_busy"))
                                })
                                return;
                            }

                            this.latest_message = { role: "assistant", content: this.getResourceString($r("app.string.welcome_words")) }
                            this.messages = []
                        })
                    }
                }
                .width("100%")
                .height("40vp")
                .padding({ left: "24vp", right: "24vp", bottom: "50vp" })

            }
            .backgroundColor('#FFFFFFFF')
            .padding({ top: '25vp', bottom: '25vp' })

        }
        .width("100%")
        .height("100%")
        .justifyContent(FlexAlign.Center)
    }

    inference = async () => {
        this.getUIContext().getFocusController().clearFocus();

        if (this.current_model.length == 0) {
            promptAction.showToast({
                message: this.getResourceString($r("app.string.warn_select_model"))
            })
            return;
        }

        if (this.num_download_task > 0) {
            promptAction.showToast({
                message: `${this.current_model} ${this.getResourceString($r("app.string.warn_download_model"))}`
            })
            return;
        }

        // Copy model files
        const work_folder: string = this.sandboxFilesDir
        const model:  string      = this.current_model
        const prompt: string      = this.jsWorkerInPutStr

        this.jsWorkerInPutStr = ""
        const prev_message: Message = this.latest_message
        this.messages.push(
            prev_message,
            { role: "user", content: prompt },
        )

        this.status = "Load"

        // This is globally required
        await this.copyFile2Sandbox('workspace.json')
        await this.copyFile2Sandbox('hparams.json')

        // Start Inference
        this.latest_message.content = ""
        if (!prompt.length) {
            this.latest_message.content = "No input for the string to be sorted.\n";
            return;
        }

        // start inference
        this.myWorker.postMessage([work_folder, model, prompt]);
        let strFlag = false;
        this.myWorker.onmessage = (e) => {
            this.status = "Infer"
            if (e.data == "[Worker DONE]") {
                strFlag = true;
                this.status = "Idle"
            } else {
                this.latest_message.content += e.data
            }
        }
        while (!strFlag) {
            await promiseCase();
        }
    }

    async downloadFile2Sandbox(model: string, filename: string) {
        const modelUrl = `${this.model_base_url}/${this.model_url_map.get(model)}/resolve/main/${filename}`

        const targetPath: string     = `${this.sandboxFilesDir}/${model}/${filename}`;
        const targetFileName: string = getFilename(targetPath);

        { // Touch the file
            let exist = await fs.access(targetPath)
            if (exist) {
                hilog.info(0x0000, 'copyFile', 'Found model file ' + filename + ' at ' + targetPath);
                return
            }
        }

        hilog.warn(0x0000, 'downloadFile',
            'Failed to find model file ' + filename + ' at ' + targetPath + ', try to download one');
        promptAction.showToast({
            message: this.getResourceString($r("app.string.warn_find_file")) + filename + ', ' + this.getResourceString($r("app.string.info_download"))
        })
        this.num_download_task += 1

        if (targetFileName.length < filename.length) { // Make parent directories if needed
            const targetDir: string      = targetPath.substring(0, targetPath.length - targetFileName.length)
            let exist = await fs.access(targetDir)
            if (!exist) {
                await fs.mkdir(targetDir)
            }
        }

        const config: request.agent.Config = {
            action:     request.agent.Action.DOWNLOAD,
            url:        modelUrl,
            method:     'GET',
            retry:      true,
            redirect:   true,
            gauge:      true,
            overwrite:  true,
            network:    request.agent.Network.ANY,
            saveas:     `./${model}/${filename}`
        };
        request.agent.create(getContext(this), config).then((task: request.agent.Task) => {
            task.start((err: BusinessError) => {
                if (err) {
                    hilog.info(0x0000, 'downloadFile', `Failed to start the download task(${modelUrl}), Code: ${err.code}, Message: ${err.message}`)
                }
                return;
            });
            task.on('progress', async(progress) => {
                hilog.info(0x0000, 'downloadFile', `/Request download ./${model}/${filename} status ${progress.state}, downloaded ${progress.processed}`);
            });
            task.on('completed', async() => {
                hilog.info(0x0000, 'downloadFile', `/Request download ./${model}/${filename} completed`);

                fs.copyFileSync(`${getContext(this).cacheDir}/${model}/${filename}`, targetPath)

                hilog.info(0x0000, 'downloadFile', `copy ./${model}/${filename} to ${targetPath} completed`);
                this.num_download_task -= 1

                if (this.num_download_task == 0) {
                    promptAction.showToast({
                        message: `${model} is downloaded`
                    })
                } else {
                    promptAction.showToast({
                        message: `${filename} ${this.getResourceString($r("app.string.info_download_files"))} ${this.num_download_task}`
                    })
                }
            });
        }).catch((err: BusinessError) => {
            hilog.info(0x0000, 'downloadFile', `Failed to start the download task(${modelUrl}), Code: ${err.code}, Message: ${err.message}`)
        });
    }

    async copyFile2Sandbox(filename: string) {
        const data: resourceManager.RawFileDescriptor = await getContext(this).resourceManager.getRawFd(filename);
        const targetPath: string = this.sandboxFilesDir + '/' + filename;
        const targetFileName: string = getFilename(targetPath);

        { // Touch the file
            let exist = await fs.access(targetPath)
            if (exist) {
                hilog.info(0x0000, 'copyFile', 'Found model file ' + filename + ' at ' + targetPath);
                return
            }
        }

        hilog.warn(0x0000, 'copyFile',
            'Failed to find model file ' + filename + ' at ' + targetPath + ', try to copy one');

        if (targetFileName.length < filename.length) { // Make parent directories if needed
            const targetDir: string      = targetPath.substring(0, targetPath.length - targetFileName.length)
            let exist = await fs.access(targetDir)
            if (!exist) {
                await fs.mkdir(targetDir)
            }
        }

        const destFile: fs.File =
            await fs.open(targetPath, fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE | fs.OpenMode.TRUNC);
        let buffSize: number = Math.min(4096 * 1024, data.length);
        const buffer: ArrayBuffer = new ArrayBuffer(Math.min(buffSize, data.length));
        // Offset of the record read position (compared with the start offset of the file)
        let readLen: number = 0;
        let off: number = 0;
        let len: number = await fs.read(data.fd, buffer, { offset: data.offset + off, length: buffSize });

        while (len > 0) {
            readLen += len;
            await fs.write(destFile.fd, buffer, { offset: off, length: len });
            off = off + len;
            if ((data.length - readLen) < buffSize) {
                buffSize = data.length - readLen;
            }
            len = await fs.read(data.fd, buffer, { offset: data.offset + off, length: buffSize });
        }
        await fs.close(destFile.fd);
    }


    getStatusString(status: "Idle" | "Load" | "Infer"): string {
        if (status == "Load") {
            return this.getResourceString($r('app.string.status_load'))
        } else if (status == "Infer") {
            return this.getResourceString($r('app.string.status_infer'))
        }
        return this.getResourceString($r('app.string.status_idle'))

    }
}

function promiseCase(): Promise<Object> {
    let p: Promise<number> = new Promise((resolve, reject) => {
        setTimeout(() => {
            resolve(1)
        }, 100)
    })
    return p;
}

function getFilename(fullPath: string): string {
    return fullPath.replace(/^.*[\\\/]/, '');
}