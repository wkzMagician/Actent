import 'package:flutter_test/flutter_test.dart';

import 'package:actent/features/actent_core/actent_models.dart';
import 'package:actent/features/actent_core/actent_store.dart';
import 'package:actent/features/actent_core/workflow_engine.dart';

void main() {
  test(
    'workflow validation locks Work revisions and adjacent pairing',
    () async {
      final repository = ActentRepository(MemoryActentJsonStore());
      await repository.saveWork(
        Work(
          id: 'download',
          revision: 2,
          name: 'Download',
          ownerDeviceId: 'desktop',
          acceptedContentTypes: {ActentContentType.url},
          outputType: ActentContentType.file,
        ),
      );
      await repository.saveWork(
        Work(
          id: 'open',
          revision: 1,
          name: 'Open',
          ownerDeviceId: 'phone',
          acceptedContentTypes: {ActentContentType.file},
          outputType: ActentContentType.none,
        ),
      );
      await repository.saveDevice(
        Device(
          id: 'desktop',
          displayName: 'Desktop',
          platform: 'windows',
          publicKey: 'desktop-key',
        ),
      );
      final workflow = Workflow(
        id: 'wf',
        revision: 1,
        name: 'Download and open',
        ownerDeviceId: 'phone',
        acceptedContentTypes: {ActentContentType.url},
        steps: const [
          WorkflowStep(
            id: 'one',
            workId: 'download',
            workRevision: 2,
            deviceId: 'desktop',
          ),
          WorkflowStep(
            id: 'two',
            workId: 'open',
            workRevision: 1,
            deviceId: 'phone',
          ),
        ],
      );

      final result = await WorkflowValidator(
        repository: repository,
        localDeviceId: 'phone',
      ).validate(workflow);

      expect(result.isValid, isTrue);
      await repository.saveWork(
        Work(
          id: 'download',
          revision: 3,
          name: 'Download changed',
          ownerDeviceId: 'desktop',
          acceptedContentTypes: {ActentContentType.url},
          outputType: ActentContentType.file,
        ),
      );
      final invalid = await WorkflowValidator(
        repository: repository,
        localDeviceId: 'phone',
      ).validate(workflow);
      expect(
        invalid.issues.map((issue) => issue.code),
        contains('work_changed'),
      );
    },
  );

  test('workflow execution state round trips and remains durable', () async {
    final repository = ActentRepository(MemoryActentJsonStore());
    final created = DateTime.utc(2026, 1, 1);
    final execution = WorkflowExecution(
      id: 'execution',
      workflowId: 'wf',
      workflowRevision: 4,
      sourceDeviceId: 'phone',
      createdAt: created,
      status: WorkflowExecutionStatus.failed,
      currentStepIndex: 1,
      error: const WorkError(code: 'work_failed', message: 'failed'),
      output: ActentPayload(type: ActentContentType.text, data: {'value': 'x'}),
    );
    await repository.saveWorkflowExecution(execution);
    final restored = await repository.getWorkflowExecution('execution');
    expect(restored!.status, WorkflowExecutionStatus.failed);
    expect(restored.currentStepIndex, 1);
    expect(restored.error!.code, 'work_failed');
    expect(restored.output!.data['value'], 'x');
  });

  test(
    'workflow runner continues a failed step from its previous output',
    () async {
      final repository = ActentRepository(MemoryActentJsonStore());
      final workA = Work(
        id: 'a',
        revision: 1,
        name: 'A',
        ownerDeviceId: 'phone',
        acceptedContentTypes: {ActentContentType.text},
        outputType: ActentContentType.text,
      );
      final workB = Work(
        id: 'b',
        revision: 1,
        name: 'B',
        ownerDeviceId: 'phone',
        acceptedContentTypes: {ActentContentType.text},
        outputType: ActentContentType.none,
      );
      await repository.saveWork(workA);
      await repository.saveWork(workB);
      final workflow = Workflow(
        id: 'wf',
        revision: 1,
        name: 'linear',
        ownerDeviceId: 'phone',
        acceptedContentTypes: {ActentContentType.text},
        steps: const [
          WorkflowStep(
            id: 'a',
            workId: 'a',
            workRevision: 1,
            deviceId: 'phone',
          ),
          WorkflowStep(
            id: 'b',
            workId: 'b',
            workRevision: 1,
            deviceId: 'phone',
          ),
        ],
      );
      var bAttempts = 0;
      Future<WorkReceipt> execute({
        required WorkflowStep step,
        required Work work,
        required ActentPayload input,
        required String executionId,
      }) async {
        if (step.id == 'b' && bAttempts++ == 0) {
          return WorkReceipt(
            requestId: executionId,
            workId: work.id,
            status: WorkReceiptStatus.failed,
            createdAt: DateTime.now().toUtc(),
            error: const WorkError(code: 'temporary'),
          );
        }
        return WorkReceipt(
          requestId: executionId,
          workId: work.id,
          status: WorkReceiptStatus.succeeded,
          createdAt: DateTime.now().toUtc(),
          output: work.outputType == ActentContentType.none
              ? null
              : ActentPayload(type: work.outputType, data: input.data),
        );
      }

      final runner = WorkflowRunner(
        repository: repository,
        validator: WorkflowValidator(
          repository: repository,
          localDeviceId: 'phone',
        ),
      );
      final failed = await runner.start(
        workflow: workflow,
        input: ActentPayload(type: ActentContentType.text, data: {'v': 'x'}),
        sourceDeviceId: 'phone',
        executeStep: execute,
        executionId: 'execution',
      );
      expect(failed.status, WorkflowExecutionStatus.failed);
      expect(failed.currentStepIndex, 1);
      expect(failed.output!.type, ActentContentType.text);
      final succeeded = await runner.continueFailed(
        workflow: workflow,
        execution: failed,
        executeStep: execute,
      );
      expect(succeeded.status, WorkflowExecutionStatus.succeeded);
      expect(bAttempts, 2);
    },
  );
}
