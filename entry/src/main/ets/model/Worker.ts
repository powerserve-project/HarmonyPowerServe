/*
 * Copyright (c) 2023 Huawei Device Co., Ltd.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

import { hilog } from '@kit.PerformanceAnalysisKit';
import { powerserveInfer, powerserveInferDestroyResponse, powerserveInferGetResponse } from 'libentry.so'
import { worker, ThreadWorkerGlobalScope, MessageEvents, ErrorEvent } from '@kit.ArkTS';
import json from '@ohos.util.json';
import { systemDateTime } from '@kit.BasicServicesKit';

let workerPort: ThreadWorkerGlobalScope = worker.workerPort;

interface ChatDelta {
  role: string,
  content: string
}

interface ChatChunk {
  index: number,
  delta: ChatDelta,
  finish_reason: string
}

interface Usage {
  prompt_tokens: number,
  completion_tokens: number,
  total_tokens: number
}

interface Response {
  id:      string,
  created: number,
  model:   string,
  choices: ChatChunk[],
  usage:   Usage
}

/**
 * Defines the event handler to be called when the worker thread receives a message sent by the host thread.
 * The event handler is executed in the worker thread.
 *
 * @param e message data
 */
workerPort.onmessage = (e: MessageEvents) => {
  const args: string[] = e.data;
  const work_folder = args[0]
  const model       = args[1]
  const prompt      = args[2]


  let request: string = `{
    "model": "${model}",
    "max_tokens": 1920,
    "stream": true,
    "messages": [ { "role": "user", "content": "${prompt}" } ]
  }`

  const start_time = systemDateTime.getTime(false)
  const response_ptr: bigint = powerserveInfer(work_folder, request);
  while (true) {
    let response_string = powerserveInferGetResponse(response_ptr);
    try {
      if (response_string.substring(0, 7) == "[ERROR]") {
        workerPort.postMessage("[Server ERROR]");
        break;
      } else if (response_string.substring(0, 12) == "data: [DONE]") {
        break
      } else if (response_string.length != 0) {
        // remove unused prefix
        if (response_string.substring(0, 5) == "data:") {
          response_string = response_string.substring(5)
        }

        // parse response format
        let response_obj: Response = json.parse(response_string) as Response
        const content: string = response_obj.choices[0].delta.content
        // send message
        workerPort.postMessage(content);
      }
    } catch (err) {
      workerPort.postMessage("[Worker ERROR]" );
      break;
    }
  }
  const end_time = systemDateTime.getTime(false)
  hilog.info(0, "Worker", `Inference speed: ${512 * 1000 / (end_time - start_time)}`);

  workerPort.postMessage("[Worker DONE]" );
  powerserveInferDestroyResponse(response_ptr);
}

/**
 * Defines the event handler to be called when the worker receives a message that cannot be deserialized.
 * The event handler is executed in the worker thread.
 *
 * @param e message data
 */
workerPort.onmessageerror = (e: MessageEvents) => {
  console.log("worker::error = " + e.data);
}

/**
 * Defines the event handler to be called when an exception occurs during worker execution.
 * The event handler is executed in the worker thread.
 *
 * @param e error message
 */
workerPort.onerror = (e: ErrorEvent) => {
}

function sleep(arg0: number) {
  throw new Error('Function not implemented.');
}
