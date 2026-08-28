import 'actent_models.dart';
import 'actent_store.dart';

class WorkflowValidationIssue {
  const WorkflowValidationIssue(this.code, this.message);

  final String code;
  final String message;

  @override
  String toString() => '$code: $message';
}

class WorkflowValidationResult {
  const WorkflowValidationResult(this.issues);

  final List<WorkflowValidationIssue> issues;
  bool get isValid => issues.isEmpty;
}

/// Validates the immutable references captured by a Workflow definition.
///
/// A workflow is valid only while every referenced Work revision still exists
/// on its declared device and every cross-device hop remains paired.
class WorkflowValidator {
  WorkflowValidator({required this.repository, required this.localDeviceId});

  final ActentRepository repository;
  final String localDeviceId;

  Future<WorkflowValidationResult> validate(Workflow workflow) async {
    final issues = <WorkflowValidationIssue>[];
    if (workflow.ownerDeviceId != localDeviceId) {
      issues.add(
        const WorkflowValidationIssue(
          'workflow_local_only',
          'workflow belongs to another device',
        ),
      );
    }
    if (!workflow.enabled) {
      issues.add(
        const WorkflowValidationIssue('disabled', 'workflow is disabled'),
      );
    }
    if (workflow.steps.isEmpty) {
      issues.add(
        const WorkflowValidationIssue('empty', 'workflow has no steps'),
      );
      return WorkflowValidationResult(issues);
    }
    final stepIds = <String>{};
    Work? previous;
    for (var index = 0; index < workflow.steps.length; index++) {
      final step = workflow.steps[index];
      if (!stepIds.add(step.id)) {
        issues.add(WorkflowValidationIssue('duplicate_step', step.id));
      }
      final work = await repository.getWork(step.workId);
      if (work == null) {
        issues.add(WorkflowValidationIssue('work_missing', step.workId));
        continue;
      }
      if (work.revision != step.workRevision) {
        issues.add(WorkflowValidationIssue('work_changed', step.workId));
      }
      if (!work.enabled) {
        issues.add(WorkflowValidationIssue('work_disabled', step.workId));
      }
      if (work.ownerDeviceId != step.deviceId) {
        issues.add(WorkflowValidationIssue('owner_mismatch', step.id));
      }
      if (index == 0 &&
          !work.acceptedContentTypes.any(
            workflow.acceptedContentTypes.contains,
          )) {
        issues.add(
          const WorkflowValidationIssue(
            'input_incompatible',
            'first Work does not accept a workflow input type',
          ),
        );
      }
      if (previous != null &&
          !work.acceptedContentTypes.contains(previous.outputType)) {
        issues.add(
          WorkflowValidationIssue(
            'output_incompatible',
            '${previous.id} output cannot enter ${work.id}',
          ),
        );
      }
      if (step.deviceId != localDeviceId) {
        issues.add(
          WorkflowValidationIssue('workflow_local_only', step.deviceId),
        );
      }
      if (index > 0 && workflow.steps[index - 1].deviceId != step.deviceId) {
        final previousDevice = workflow.steps[index - 1].deviceId;
        if (previousDevice != localDeviceId) {
          final device = await repository.getDevice(previousDevice);
          if (device == null || !device.authorized) {
            issues.add(
              WorkflowValidationIssue('workflow_local_only', previousDevice),
            );
          }
        }
      }
      previous = work;
    }
    return WorkflowValidationResult(issues);
  }
}

typedef WorkflowStepExecutor = Future<WorkReceipt> Function({
  required WorkflowStep step,
  required Work work,
  required ActentPayload input,
  required String executionId,
});

/// Runs a validated linear workflow and persists every durable transition.
///
/// The executor is supplied by application composition. This keeps Work
/// execution and transport out of the generic model layer while allowing the
/// same coordinator to dispatch local and paired remote steps.
class WorkflowRunner {
  WorkflowRunner({required this.repository, required this.validator});

  final ActentRepository repository;
  final WorkflowValidator validator;

  Future<WorkflowExecution> start({
    required Workflow workflow,
    required ActentPayload input,
    required String sourceDeviceId,
    required WorkflowStepExecutor executeStep,
    String? executionId,
  }) async {
    final validation = await validator.validate(workflow);
    if (!validation.isValid) {
      final execution = WorkflowExecution(
        id: executionId ?? 'workflow-${DateTime.now().microsecondsSinceEpoch}',
        workflowId: workflow.id,
        workflowRevision: workflow.revision,
        sourceDeviceId: sourceDeviceId,
        createdAt: DateTime.now().toUtc(),
        status: WorkflowExecutionStatus.invalid,
        error: WorkError(
          code: 'workflow_invalid',
          message: validation.issues
              .map((issue) => issue.toString())
              .join('; '),
        ),
      );
      await repository.saveWorkflowExecution(execution);
      return execution;
    }
    final execution = WorkflowExecution(
      id: executionId ?? 'workflow-${DateTime.now().microsecondsSinceEpoch}',
      workflowId: workflow.id,
      workflowRevision: workflow.revision,
      sourceDeviceId: sourceDeviceId,
      createdAt: DateTime.now().toUtc(),
      status: WorkflowExecutionStatus.queued,
    );
    return _run(
      workflow: workflow,
      execution: execution,
      input: input,
      executeStep: executeStep,
      startIndex: 0,
    );
  }

  /// Continue reruns the failed step using the previous step's persisted
  /// output. It never silently restarts the entire workflow (that is retry).
  Future<WorkflowExecution> continueFailed({
    required Workflow workflow,
    required WorkflowExecution execution,
    required WorkflowStepExecutor executeStep,
  }) async {
    if (execution.status != WorkflowExecutionStatus.failed ||
        execution.output == null ||
        execution.currentStepIndex >= workflow.steps.length) {
      return execution;
    }
    final validation = await validator.validate(workflow);
    if (!validation.isValid ||
        execution.workflowRevision != workflow.revision) {
      final invalid = _failed(
        execution,
        WorkflowExecutionStatus.invalid,
        WorkError(code: 'workflow_changed'),
      );
      await repository.saveWorkflowExecution(invalid);
      return invalid;
    }
    return _run(
      workflow: workflow,
      execution: execution,
      input: execution.output!,
      executeStep: executeStep,
      startIndex: execution.currentStepIndex,
    );
  }

  Future<WorkflowExecution> _run({
    required Workflow workflow,
    required WorkflowExecution execution,
    required ActentPayload input,
    required WorkflowStepExecutor executeStep,
    required int startIndex,
  }) async {
    var current = _with(execution, status: WorkflowExecutionStatus.running);
    await repository.saveWorkflowExecution(current);
    var value = input;
    for (var index = startIndex; index < workflow.steps.length; index++) {
      final step = workflow.steps[index];
      final work = await repository.getWork(step.workId);
      if (work == null) {
        current = _failed(
          current,
          WorkflowExecutionStatus.invalid,
          WorkError(code: 'work_missing', details: {'workId': step.workId}),
        );
        await repository.saveWorkflowExecution(current);
        return current;
      }
      current = _with(current, currentStepIndex: index);
      await repository.saveWorkflowExecution(current);
      late WorkReceipt receipt;
      try {
        receipt = await executeStep(
          step: step,
          work: work,
          input: value,
          executionId: execution.id,
        );
      } on Object catch (error) {
        current = _failed(
          current,
          WorkflowExecutionStatus.failed,
          WorkError(code: 'step_dispatch_failed', message: '$error'),
        );
        await repository.saveWorkflowExecution(current);
        return current;
      }
      if (receipt.status != WorkReceiptStatus.succeeded) {
        current = _failed(
          current,
          WorkflowExecutionStatus.failed,
          receipt.error ?? WorkError(code: receipt.errorCode ?? 'work_failed'),
          output: value,
        );
        await repository.saveWorkflowExecution(current);
        return current;
      }
      if (index == workflow.steps.length - 1) {
        current = _with(
          current,
          status: WorkflowExecutionStatus.succeeded,
          output: receipt.output,
        );
        await repository.saveWorkflowExecution(current);
        return current;
      }
      if (receipt.output == null) {
        current = _failed(
          current,
          WorkflowExecutionStatus.failed,
          WorkError(code: 'missing_step_output'),
        );
        await repository.saveWorkflowExecution(current);
        return current;
      }
      value = receipt.output!;
      current = _with(current, output: value);
      await repository.saveWorkflowExecution(current);
    }
    return current;
  }

  WorkflowExecution _failed(
    WorkflowExecution execution,
    WorkflowExecutionStatus status,
    WorkError error, {
    ActentPayload? output,
  }) => _with(execution, status: status, error: error, output: output);

  WorkflowExecution _with(
    WorkflowExecution execution, {
    WorkflowExecutionStatus? status,
    int? currentStepIndex,
    WorkError? error,
    ActentPayload? output,
  }) => WorkflowExecution(
    id: execution.id,
    workflowId: execution.workflowId,
    workflowRevision: execution.workflowRevision,
    sourceDeviceId: execution.sourceDeviceId,
    createdAt: execution.createdAt,
    status: status ?? execution.status,
    currentStepIndex: currentStepIndex ?? execution.currentStepIndex,
    updatedAt: DateTime.now().toUtc(),
    error: error,
    output: output,
  );
}
